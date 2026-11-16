extends Node
class_name SerialLink

## Enlace serial con el firmware del laboratorio (GdSerial).
##
## Protocolo: 9600 8N1, mensajes de texto terminados en '\n'
##   Godot   -> Arduino : "A:<angulo>"
##   Arduino -> Godot   : "S:<angulo>,<fuente>"   (POT | DIG)
##
## La lectura es no bloqueante: se consulta bytes_available() y solo se lee
## cuando hay datos, con timeout 0 como red de seguridad.

signal estado_recibido(angulo: int, fuente: String)
signal conexion_cambiada(conectado: bool, mensaje: String)

@export var baudios: int = 9600

var _serial: GdSerial
var _buffer: String = ""
var _conectado: bool = false
var _puerto: String = ""

func _ready() -> void:
	set_process(false)

func conectar(puerto: String = "") -> bool:
	desconectar()

	var objetivo := puerto.strip_edges()
	if objetivo.is_empty():
		objetivo = puerto_automatico()

	if objetivo.is_empty():
		conexion_cambiada.emit(false, "No se encontró ningún puerto serial")
		return false

	var instancia := GdSerial.new()
	instancia.set_port(objetivo)
	instancia.set_baud_rate(baudios)
	instancia.set_data_bits(8)
	instancia.set_parity(0)          # sin paridad
	instancia.set_stop_bits(1)
	instancia.set_flow_control(0)    # sin control de flujo
	instancia.set_timeout(0)         # ninguna lectura puede esperar

	if not instancia.open():
		conexion_cambiada.emit(false, "No se pudo abrir %s" % objetivo)
		return false

	_serial = instancia
	_puerto = objetivo
	_buffer = ""
	_conectado = true
	set_process(true)
	conexion_cambiada.emit(true, "Conectado a %s" % objetivo)
	return true

func desconectar() -> void:
	set_process(false)
	if _serial != null:
		_serial.close()
		_serial = null
	if _conectado:
		_conectado = false
		_puerto = ""
		conexion_cambiada.emit(false, "Desconectado")

func esta_conectado() -> bool:
	return _conectado

func puerto_actual() -> String:
	return _puerto

func enviar_angulo(angulo: int) -> void:
	if not _conectado or _serial == null:
		return
	_serial.writeline("A:%d" % clampi(angulo, 0, 180))

func puerto_automatico() -> String:
	var sonda := GdSerial.new()
	var puertos: Dictionary = sonda.list_ports()
	for indice in puertos:
		var nombre: String = puertos[indice]["port_name"]
		if nombre.contains("ACM") or nombre.contains("USB") or nombre.begins_with("COM"):
			return nombre
	return ""

func _process(_delta: float) -> void:
	if not _conectado or _serial == null:
		return

	var disponibles := _serial.bytes_available()
	if disponibles > 0:
		_buffer += _serial.read_string(disponibles)

	_procesar_lineas()

func _procesar_lineas() -> void:
	while true:
		var fin := _buffer.find("\n")
		if fin == -1:
			break
		var linea := _buffer.substr(0, fin).strip_edges()
		_buffer = _buffer.substr(fin + 1)
		if linea.begins_with("S:"):
			_interpretar_reporte(linea.substr(2))

	if _buffer.length() > 256:
		_buffer = ""   # desincronización o basura: se descarta

func _interpretar_reporte(campos: String) -> void:
	var partes := campos.split(",")
	if partes.size() != 2:
		return
	if not partes[0].is_valid_int():
		return

	var angulo := int(partes[0])
	if angulo < 0 or angulo > 180:
		return

	var fuente := partes[1]
	if fuente != "POT" and fuente != "DIG":
		return

	estado_recibido.emit(angulo, fuente)
