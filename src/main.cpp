// ===========================================================================
//  Laboratorio de clase — Gemelo digital con servomotor
//  Situación 7: radar de vigilancia
//
//  Placa: Arduino Nano (ATmega328P, 5 V / 16 MHz)
//
//  Mando físico:  potenciómetro en A0
//  Actuador:      servomotor en D4 (señal de control)
//
//  Enlace serial (9600 baudios, 8N1, mensajes terminados en '\n'):
//      Godot  -> Arduino : "A:<angulo>\n"           ángulo 0..180
//      Arduino -> Godot : "S:<angulo>,<fuente>\n"   fuente POT | DIG
//
//  El ciclo principal no usa delay(): todo se temporiza con millis().
// ===========================================================================

#include <Arduino.h>
#include <Servo.h>

/* -------------------------------- Pines --------------------------------- */

const uint8_t PIN_POT   = A0;   // mando físico
const uint8_t PIN_SERVO = 4;    // D4

/* ---------------------------- Calibración -------------------------------- */

// Rango del ADC que corresponde al recorrido útil del potenciómetro.
// Con el potenciómetro conectado entre 5 V y GND el recorrido completo es
// 0..1023; si el montaje no llega a los extremos, se ajustan estos valores
// para que el servo use todo su recorrido sin pegar contra los topes.
const int POT_ADC_MIN = 0;
const int POT_ADC_MAX = 1023;

// Muestras promediadas por lectura. Con el servo en movimiento la rail de 5 V
// se ensucia y una sola conversión puede desviarse varios grados; promediar 8
// reduce el ruido aleatorio en un factor ~raiz(8) ≈ 2,8 sin costo apreciable
// (8 conversiones ≈ 0,9 ms cada 20 ms).
const uint8_t MUESTRAS_POT = 8;

const int ANGULO_MIN = 0;
const int ANGULO_MAX = 180;

// Sentido de la salida del servo. Con true se escribe 180 - ángulo, para los
// montajes en los que el eje queda girado 180° respecto al sentido esperado.
// El potenciómetro y los reportes S: no cambian: siguen en el dominio lógico.
const bool INVERTIR_SALIDA_SERVO = true;

/* ----------------------------- Temporización ----------------------------- */

// Muestreo del potenciómetro y avance del servo. 20 ms = 50 Hz: suficiente
// para que el movimiento se vea continuo y para reaccionar al mando digital.
const uint16_t PERIODO_CONTROL_MS = 20;

// Reporte de estado. 100 ms = 10 reportes/s: deja ver los ángulos intermedios
// del movimiento progresivo (a 360 °/s son ~36° entre reportes) y ocupa poco
// enlace (10 bytes por mensaje ≈ 10,4 ms a 9600 baudios, ~10 % del tiempo).
const uint16_t PERIODO_REPORTE_MS = 100;

// Velocidad máxima de giro. El SG90 tarda ~0,1 s por 60° (≈600 °/s), así que
// 360 °/s queda por debajo del límite físico: el perfil se cumple de verdad.
const float VELOCIDAD_MAX_DEG_S = 360.0f;

/* ------------------------------- Arbitraje ------------------------------- */

// Política "último mando que actúa gana", con histéresis en el potenciómetro:
//   - Un comando A: válido fija el objetivo y la fuente DIG.
//   - El potenciómetro recupera el mando cuando se aparta de su posición de
//     referencia (la que tenía al llegar el comando) más que esta histéresis.
// Umbral para que el potenciómetro retome el mando cuando lo tiene el digital.
// Se midió en el montaje: con el servo quieto la lectura es estable, pero
// mientras gira aparecen desviaciones de varios grados, así que el umbral es
// amplio (5°) y además la retoma debe sostenerse varios ciclos seguidos.
const int HISTERESIS_RETOMA_DEG = 5;

// Umbral para seguir al potenciómetro cuando ya tiene el mando. No puede ser
// 0 ni 1: con umbral de 1° cualquier variación de una décima hace que el servo
// haga una corrección, esa corriente ensucia la lectura y se realimenta el
// ruido (se midió una oscilación de ±4,5° con el potenciómetro quieto). Con 2°
// el servo queda quieto y la lectura se estabiliza.
const int UMBRAL_SEGUIMIENTO_DEG = 2;

// Ciclos consecutivos (20 ms cada uno) que el potenciómetro debe mantenerse
// fuera del umbral antes de retomar el mando: descarta picos aislados.
const uint8_t TICS_CONFIRMACION = 3;

// Tras una retoma del mando físico, los comandos A: se ignoran durante este
// tiempo. Evita que el software pelee con la mano del usuario: primero se
// suelta el potenciómetro y solo después la escena vuelve a mandar.
const uint16_t BLOQUEO_TRAS_RETOMA_MS = 500;

/* -------------------------------- Serial --------------------------------- */

const unsigned long SERIAL_BAUD = 9600;

// "A:180\n" son 6 caracteres; 16 deja margen y acota el búfer.
const uint8_t MAX_LINEA = 16;

/* -------------------------------- Estado --------------------------------- */

enum Fuente : uint8_t { FUENTE_POT = 0, FUENTE_DIG = 1 };

Servo servo;

int potActual = 90;        // última lectura convertida a grados
int potAncla = 90;         // referencia para la retoma del mando físico
int anguloObjetivo = 90;   // a dónde debe llegar el servo
float anguloOrdenado = 90.0f;  // ángulo que se está ordenando ahora mismo
Fuente fuente = FUENTE_POT;

unsigned long tControl = 0;
unsigned long tReporte = 0;

char linea[MAX_LINEA];
uint8_t nLinea = 0;
bool lineaDescartada = false;

uint8_t ticsFueraDeUmbral = 0;   // confirmación de la retoma del mando físico
bool bloqueoActivo = false;      // se ignoran los A: mientras dure
unsigned long tRetomaMs = 0;

/* -------------------------------- Utilidades ----------------------------- */

int leerPotenciometro() {
	uint16_t suma = 0;
	for (uint8_t i = 0; i < MUESTRAS_POT; i++) {
		suma += analogRead(PIN_POT);
	}

	int adc = suma / MUESTRAS_POT;
	if (adc < POT_ADC_MIN) adc = POT_ADC_MIN;
	if (adc > POT_ADC_MAX) adc = POT_ADC_MAX;

	long rango = POT_ADC_MAX - POT_ADC_MIN;
	long grados = (long)(adc - POT_ADC_MIN) * (ANGULO_MAX - ANGULO_MIN);

	if (rango <= 0) return ANGULO_MIN;

	// Redondeo al entero más cercano en lugar de truncar.
	return ANGULO_MIN + (int)((grados + rango / 2) / rango);
}

// Punto único de salida hacia el servo: aquí se aplica el sentido del montaje.
void escribirServo(int angulo) {
	servo.write(INVERTIR_SALIDA_SERVO ? (ANGULO_MIN + ANGULO_MAX - angulo) : angulo);
}

// Acepta exclusivamente "A:<entero 0..180>". Descarta cualquier otra cosa:
// prefijos ajenos, signos, espacios, texto o valores fuera de rango.
bool parsearComando(const char *s, int *salida) {
	if (s[0] != 'A' || s[1] != ':') return false;

	const char *p = s + 2;
	if (*p == '\0') return false;

	int valor = 0;
	uint8_t digitos = 0;

	while (*p != '\0') {
		if (*p < '0' || *p > '9') return false;

		valor = valor * 10 + (*p - '0');
		if (valor > ANGULO_MAX) return false;   // corta 181, 200, 1000...
		if (++digitos > 3) return false;

		p++;
	}

	*salida = valor;
	return true;
}

void aplicarComandoDigital(int angulo) {
	if (bloqueoActivo) {
		if (millis() - tRetomaMs < BLOQUEO_TRAS_RETOMA_MS) {
			return;   // el mando físico acaba de tomar el control
		}
		bloqueoActivo = false;
	}

	anguloObjetivo = angulo;
	fuente = FUENTE_DIG;
	// Ancla: la posición del potenciómetro en este instante. Para recuperar
	// el mando físico habrá que moverlo más que la histéresis desde aquí,
	// y sostenerlo varios ciclos seguidos.
	potAncla = potActual;
	ticsFueraDeUmbral = 0;
}

/* ------------------------------ Control ---------------------------------- */

void actualizarControl(unsigned long ahora) {
	potActual = leerPotenciometro();

	if (fuente == FUENTE_POT) {
		// El mando físico manda mientras se mueva; si está quieto se conserva
		// el último objetivo para no temblar con el ruido.
		if (abs(potActual - anguloObjetivo) >= UMBRAL_SEGUIMIENTO_DEG) {
			anguloObjetivo = potActual;
		}
		potAncla = potActual;
	} else if (abs(potActual - potAncla) >= HISTERESIS_RETOMA_DEG) {
		// Movimiento sostenido del potenciómetro: retoma el mando.
		if (++ticsFueraDeUmbral >= TICS_CONFIRMACION) {
			fuente = FUENTE_POT;
			anguloObjetivo = potActual;
			potAncla = potActual;
			ticsFueraDeUmbral = 0;
			bloqueoActivo = true;
			tRetomaMs = ahora;
		}
	} else {
		ticsFueraDeUmbral = 0;
	}

	// Avance progresivo hacia el objetivo (limitador de velocidad).
	float dt = (ahora - tControl) / 1000.0f;
	if (dt > 0.1f) dt = 0.1f;   // si el ciclo se retrasó, no dar un salto

	float pasoMax = VELOCIDAD_MAX_DEG_S * dt;
	float error = anguloObjetivo - anguloOrdenado;

	if (fabs(error) <= pasoMax) {
		anguloOrdenado = anguloObjetivo;
	} else {
		anguloOrdenado += (error > 0.0f) ? pasoMax : -pasoMax;
	}

	escribirServo((int)(anguloOrdenado + 0.5f));
}

/* ------------------------------- Serial ---------------------------------- */

// Recibe y procesa todo lo disponible sin esperar a nadie. Solo se interpreta
// un mensaje cuando llega el '\n': los fragmentos quedan en el búfer.
void atenderSerial() {
	while (Serial.available() > 0) {
		char c = (char)Serial.read();

		if (c == '\n') {
			if (!lineaDescartada && nLinea > 0) {
				linea[nLinea] = '\0';
				int angulo;
				if (parsearComando(linea, &angulo)) {
					aplicarComandoDigital(angulo);
				}
			}
			nLinea = 0;
			lineaDescartada = false;
		} else if (c != '\r') {
			if (nLinea < MAX_LINEA - 1) {
				linea[nLinea++] = c;
			} else {
				lineaDescartada = true;   // línea demasiado larga: se tira
				nLinea = 0;
			}
		}
	}
}

void enviarReporte() {
	int angulo = (int)(anguloOrdenado + 0.5f);

	Serial.print(F("S:"));
	Serial.print(angulo);
	Serial.print(',');
	Serial.print(fuente == FUENTE_POT ? F("POT") : F("DIG"));
	Serial.write('\n');
}

/* -------------------------------- Setup ---------------------------------- */

void setup() {
	Serial.begin(SERIAL_BAUD);

	pinMode(PIN_POT, INPUT);
	servo.attach(PIN_SERVO);

	// Arrancar en la posición del mando físico evita un salto al energizar.
	potActual = leerPotenciometro();
	potAncla = potActual;
	anguloObjetivo = potActual;
	anguloOrdenado = (float)potActual;
	escribirServo(potActual);

	tControl = millis();
	tReporte = tControl;
}

/* --------------------------------- Loop ---------------------------------- */

void loop() {
	atenderSerial();

	unsigned long ahora = millis();

	if (ahora - tControl >= PERIODO_CONTROL_MS) {
		// tControl todavía guarda el instante del tick anterior: de ahí sale
		// el dt que usa actualizarControl() para el avance progresivo.
		actualizarControl(ahora);
		tControl = ahora;
	}

	if (ahora - tReporte >= PERIODO_REPORTE_MS) {
		tReporte = ahora;
		// En el Nano (serial por hardware) la condición siempre es verdadera.
		// En placas con USB nativo evita escribir si el host no abrió el puerto,
		// que es cuando la escritura podría quedarse esperando.
		if (Serial) enviarReporte();
	}
}
