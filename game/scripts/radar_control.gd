extends Control

## Control de la escena del radar.
##
## - Refleja siempre el ángulo que reporta el servo (fuente de verdad).
## - El deslizador envía el mando digital (A:) sin reenviar lo que llega.
## - La rutina de barrido envía comandos periódicos; se cancela en cuanto el
##   potenciómetro toma el mando (reporte POT) o el usuario mueve el deslizador.

const RUTINA_MIN := 10.0
const RUTINA_MAX := 170.0
const RUTINA_PASO := 3.0
const RUTINA_PERIODO := 0.05      # 20 comandos por segundo
const ENVIO_MINIMO := 0.04        # separación mínima entre comandos manuales
const ESPERA_DIG := 0.5           # gracia antes de creer en un reporte POT

@onready var _serial: SerialLink = $SerialLink
@onready var _radar: Control = $HBox/RadarDisplay
@onready var _puerto: LineEdit = $HBox/PanelControl/FilaPuerto/LineEditPuerto
@onready var _boton_conectar: Button = $HBox/PanelControl/FilaPuerto/BotonConectar
@onready var _estado: Label = $HBox/PanelControl/EstadoConexion
@onready var _etiqueta_angulo: Label = $HBox/PanelControl/EtiquetaAngulo
@onready var _etiqueta_fuente: Label = $HBox/PanelControl/EtiquetaFuente
@onready var _etiqueta_slider: Label = $HBox/PanelControl/EtiquetaSlider
@onready var _slider: HSlider = $HBox/PanelControl/SliderPosicion
@onready var _boton_rutina: Button = $HBox/PanelControl/BotonRutina
@onready var _boton_detener: Button = $HBox/PanelControl/BotonDetener
@onready var _log: Label = $HBox/PanelControl/Log

var _angulo_servo: int = 90
var _fuente: String = "POT"

var _rutina_activa := false
var _rutina_objetivo := 90.0
var _rutina_direccion := 1.0
var _rutina_t := 0.0
var _rutina_esperando_dig := false
var _rutina_espera := 0.0

var _pendiente_envio := -1
var _t_envio := 0.0
var _arrastrando := false

func _ready() -> void:
	_serial.estado_recibido.connect(_al_recibir_estado)
	_serial.conexion_cambiada.connect(_al_cambiar_conexion)

	_slider.value_changed.connect(_al_mover_slider)
	_slider.drag_started.connect(func() -> void: _arrastrando = true)
	_slider.drag_ended.connect(func(_cambiado: bool) -> void: _arrastrando = false)
	_boton_rutina.pressed.connect(_al_pulsar_rutina)
	_boton_detener.pressed.connect(_al_pulsar_detener)
	_boton_conectar.pressed.connect(_al_pulsar_conectar)

	_radar.set_angulo(_angulo_servo)
	_actualizar_botones()
	_registrar("Buscando el puerto serial…")
	_serial.conectar(_puerto.text)

func _process(delta: float) -> void:
	# Envío manual limitado en frecuencia: arrastrar el deslizador puede
	# generar decenas de eventos por segundo y saturaría el enlace.
	_t_envio += delta
	if _pendiente_envio >= 0 and _t_envio >= ENVIO_MINIMO:
		_serial.enviar_angulo(_pendiente_envio)
		_pendiente_envio = -1
		_t_envio = 0.0

	if _rutina_activa:
		if _rutina_esperando_dig:
			_rutina_espera += delta
			if _rutina_espera >= ESPERA_DIG:
				_rutina_esperando_dig = false

		_rutina_t += delta
		if _rutina_t >= RUTINA_PERIODO:
			_rutina_t = 0.0
			_paso_rutina()

func _al_recibir_estado(angulo: int, fuente: String) -> void:
	_angulo_servo = angulo
	_fuente = fuente

	# La escena sigue siempre al servo, venga de donde venga el mando.
	_radar.set_angulo(float(angulo))
	# Sin emitir señal: actualizar el control no es una orden. Mientras el
	# usuario lo arrastra no se toca, para que no se le escape el pulgar.
	if not _arrastrando:
		_slider.set_value_no_signal(float(angulo))
		_etiqueta_slider.text = "Posición manual: %d°" % angulo
	_etiqueta_angulo.text = "Servo: %d°" % angulo
	_etiqueta_fuente.text = "Mando: %s" % _nombre_fuente(fuente)
	_etiqueta_fuente.add_theme_color_override(
		"font_color",
		Color(1.0, 0.80, 0.35) if fuente == "POT" else Color(0.45, 0.85, 1.0)
	)

	if not _rutina_activa:
		return

	if fuente == "DIG":
		_rutina_esperando_dig = false
		_rutina_espera = 0.0
	elif not _rutina_esperando_dig:
		_cancelar_rutina("Rutina cancelada: el potenciómetro tomó el mando")

func _al_mover_slider(valor: float) -> void:
	_etiqueta_slider.text = "Posición manual: %d°" % int(valor)
	if _rutina_activa:
		_cancelar_rutina("Rutina cancelada: mando manual desde la escena")
	_pendiente_envio = int(valor)

func _al_pulsar_rutina() -> void:
	if _rutina_activa:
		_cancelar_rutina("Rutina detenida")
		return
	if not _serial.esta_conectado():
		_registrar("Conecta el puerto antes de iniciar la rutina")
		return

	_rutina_activa = true
	_rutina_objetivo = float(_angulo_servo)
	_rutina_direccion = 1.0
	_rutina_t = 0.0
	_rutina_espera = 0.0
	_rutina_esperando_dig = true
	_pendiente_envio = -1
	_serial.enviar_angulo(int(_rutina_objetivo))
	_registrar("Rutina de barrido activa (%.0f°–%.0f°)" % [RUTINA_MIN, RUTINA_MAX])
	_actualizar_botones()

func _al_pulsar_detener() -> void:
	_cancelar_rutina("Rutina detenida")

func _al_pulsar_conectar() -> void:
	if _serial.esta_conectado():
		_serial.desconectar()
	else:
		_serial.conectar(_puerto.text)

func _paso_rutina() -> void:
	_rutina_objetivo += _rutina_direccion * RUTINA_PASO
	if _rutina_objetivo >= RUTINA_MAX:
		_rutina_objetivo = RUTINA_MAX
		_rutina_direccion = -1.0
	elif _rutina_objetivo <= RUTINA_MIN:
		_rutina_objetivo = RUTINA_MIN
		_rutina_direccion = 1.0

	_serial.enviar_angulo(int(_rutina_objetivo))

func _cancelar_rutina(motivo: String) -> void:
	if not _rutina_activa:
		return
	_rutina_activa = false
	_rutina_esperando_dig = false
	_registrar(motivo)
	_actualizar_botones()

func _al_cambiar_conexion(conectado: bool, mensaje: String) -> void:
	_estado.text = mensaje
	_estado.add_theme_color_override(
		"font_color",
		Color(0.55, 0.95, 0.60) if conectado else Color(1.0, 0.55, 0.55)
	)
	_boton_conectar.text = "Desconectar" if conectado else "Conectar"
	if conectado:
		_puerto.text = _serial.puerto_actual()
	else:
		_cancelar_rutina("Rutina detenida: puerto desconectado")
	_actualizar_botones()

func _actualizar_botones() -> void:
	_boton_rutina.text = "Detener rutina" if _rutina_activa else "Iniciar rutina"
	_boton_rutina.disabled = not _serial.esta_conectado()
	_boton_detener.disabled = not _rutina_activa

func _registrar(mensaje: String) -> void:
	_log.text = mensaje

func _nombre_fuente(fuente: String) -> String:
	return "físico (potenciómetro)" if fuente == "POT" else "digital (escena)"
