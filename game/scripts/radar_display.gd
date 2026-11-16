extends Control

## Pantalla de radar en semicírculo (situación 7).
##
## El centro del semicírculo está en la base del control y el arco va de -90°
## (izquierda) a +90° (derecha), pasando por 0° (arriba). El ángulo del
## servomotor (0..180°) se mapea directamente a ese arco:
##   0° -> -90°, 90° -> 0°, 180° -> +90°.
##
## Los blancos se desplazan dentro del arco y solo se iluminan cuando el haz
## pasa por su azimut.

@export var azimut_min: float = -90.0
@export var azimut_max: float = 90.0
@export var margen_haz: float = 3.0
@export var tiempo_resalte: float = 1.5
@export var velocidad_barrido: float = 720.0   # °/s para alcanzar el ángulo
@export var margen_exterior: float = 16.0

const COL_FONDO := Color(0.03, 0.10, 0.07)
const COL_REJILLA := Color(0.15, 0.55, 0.35, 0.55)
const COL_HAZ := Color(0.30, 1.00, 0.55)
const COL_BLANCO := Color(1.00, 0.85, 0.30)
const COL_TEXTO := Color(0.75, 1.00, 0.85)

var angulo_servo: float = 90.0

var _azimut: float = 0.0
var _azimut_previo: float = 0.0
var _azimut_objetivo: float = 0.0
var _objetivos: Array[Dictionary] = []
var _tiempo: float = 0.0

func _ready() -> void:
	_objetivos = [
		{"azimut": -62.0, "radio": 0.55, "velocidad": 4.0, "visto": -999.0},
		{"azimut": 18.0, "radio": 0.84, "velocidad": -3.0, "visto": -999.0},
		{"azimut": 55.0, "radio": 0.40, "velocidad": 5.0, "visto": -999.0},
		{"azimut": -28.0, "radio": 0.70, "velocidad": -2.0, "visto": -999.0},
		{"azimut": 74.0, "radio": 0.60, "velocidad": 3.5, "visto": -999.0},
	]

func _process(delta: float) -> void:
	_tiempo += delta

	for objetivo in _objetivos:
		var azimut: float = float(objetivo["azimut"]) + float(objetivo["velocidad"]) * delta
		if azimut > azimut_max:
			azimut = azimut_max
			objetivo["velocidad"] = -float(objetivo["velocidad"])
		elif azimut < azimut_min:
			azimut = azimut_min
			objetivo["velocidad"] = -float(objetivo["velocidad"])
		objetivo["azimut"] = azimut

	# La antena se mueve hacia el ángulo reportado a velocidad acotada, para
	# que el barrido no salte con cada reporte (10 por segundo).
	_azimut_previo = _azimut
	var diferencia := _azimut_objetivo - _azimut
	var paso := velocidad_barrido * delta
	if absf(diferencia) <= paso:
		_azimut = _azimut_objetivo
	else:
		_azimut += signf(diferencia) * paso

	_detectar()
	queue_redraw()

func set_angulo(grados: float) -> void:
	angulo_servo = clampf(grados, 0.0, 180.0)
	_azimut_objetivo = lerpf(azimut_min, azimut_max, angulo_servo / 180.0)

func _detectar() -> void:
	for objetivo in _objetivos:
		if _barrido_cubre(_azimut_previo, _azimut, float(objetivo["azimut"])):
			objetivo["visto"] = _tiempo

func _barrido_cubre(desde: float, hasta: float, objetivo: float) -> bool:
	var recorrido := hasta - desde
	var posicion := objetivo - desde
	if recorrido >= 0.0:
		return posicion >= -margen_haz and posicion <= recorrido + margen_haz
	return posicion <= margen_haz and posicion >= recorrido - margen_haz

func _draw() -> void:
	var centro := Vector2(size.x * 0.5, size.y - margen_exterior)
	var radio: float = minf(size.x * 0.5, size.y - margen_exterior) - margen_exterior
	if radio <= 20.0:
		return

	# Semicírculo de fondo: centro + arco superior.
	var contorno := PackedVector2Array([centro])
	for indice in range(0, 49):
		contorno.append(centro + _direccion(lerpf(azimut_min, azimut_max, indice / 48.0)) * radio)
	draw_colored_polygon(contorno, COL_FONDO)

	# Anillos y radios.
	for anillo in range(1, 4):
		draw_arc(centro, radio * anillo / 3.0, PI, TAU, 64, COL_REJILLA, 1.0, true)
	draw_arc(centro, radio, PI, TAU, 96, COL_REJILLA, 2.0, true)
	for marca in [-90.0, -60.0, -30.0, 0.0, 30.0, 60.0, 90.0]:
		draw_line(centro, centro + _direccion(marca) * radio, COL_REJILLA, 1.0)

	# Haz de la antena.
	var haz_a := _direccion(clampf(_azimut - 4.0, azimut_min, azimut_max))
	var haz_b := _direccion(clampf(_azimut + 4.0, azimut_min, azimut_max))
	draw_colored_polygon(
		PackedVector2Array([centro, centro + haz_a * radio, centro + haz_b * radio]),
		Color(COL_HAZ.r, COL_HAZ.g, COL_HAZ.b, 0.16)
	)
	draw_line(centro, centro + _direccion(_azimut) * radio, COL_HAZ, 2.5, true)

	# Blancos detectados.
	for objetivo in _objetivos:
		var edad: float = _tiempo - float(objetivo["visto"])
		var alfa := clampf(1.0 - edad / tiempo_resalte, 0.0, 1.0)
		if alfa <= 0.02:
			continue
		var punto := centro + _direccion(float(objetivo["azimut"])) * radio * float(objetivo["radio"])
		var color := Color(COL_BLANCO.r, COL_BLANCO.g, COL_BLANCO.b, alfa)
		draw_circle(punto, 6.0, color)
		draw_arc(punto, 11.0, 0.0, TAU, 24, Color(color.r, color.g, color.b, alfa * 0.7), 1.5, true)

	var fuente := ThemeDB.fallback_font
	draw_string(fuente, Vector2(12, 26), "Antena: %d°" % int(round(angulo_servo)),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, COL_TEXTO)
	draw_string(fuente, Vector2(12, 48), "Barrido: %d°" % int(round(_azimut)),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, COL_TEXTO)

func _direccion(azimut: float) -> Vector2:
	var rad := deg_to_rad(azimut)
	return Vector2(sin(rad), -cos(rad))
