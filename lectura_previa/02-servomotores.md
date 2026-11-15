# 2. Servomotores de posición y la librería `Servo.h`

**Guía de lectura del pre-laboratorio** · Tema 2 del enunciado
**Tiempo estimado:** 60–90 min · **Fuentes al final del documento**

---

## 2.1. Qué debe quedar claro

Al terminar esta lectura debe poder explicar, sin consultar:

1. Qué hay dentro de un servomotor de posición y por qué puede **mantener** un ángulo.
2. Cómo se codifica el ángulo en la señal de control y qué significa "PWM de 50 Hz".
3. Qué hace exactamente `Servo.write()` y qué devuelve `Servo.read()`.
4. Por qué usar `Servo.h` **quita** funciones PWM del Arduino y con qué temporizador trabaja.
5. En qué se diferencia un servo de posición de uno de rotación continua y por qué este
   laboratorio no admite el segundo.

---

## 2.2. Arquitectura interna de un servomotor de posición

Un servo de hobby (SG90, MG90S, MG996R) no es un motor "inteligente": es un **lazo de control
cerrado** metido en una caja. Sus piezas son:

| Pieza | Función |
| --- | --- |
| Motor DC | Entrega el par; gira en un sentido u otro según la polaridad. |
| Tren de engranajes | Reduce la velocidad y multiplica el par. |
| Potenciómetro interno | Mide la posición **del eje de salida**; es el sensor de realimentación. |
| Circuito de control | Compara la orden con la lectura del potenciómetro y corrige la polaridad y el ciclo de trabajo del motor. |
| Tope mecánico | Limita el recorrido a un rango útil (típicamente 180°). |

Consecuencia directa: **el servo no sabe cuál es su ángulo absoluto hasta que el
potenciómetro interno lo dice**. A diferencia de un motor paso a paso, no lleva cuenta de
pasos: corrige el error hasta anularlo. Eso explica que mantenga la posición ante una carga
externa y que "empuje" si alguien intenta moverlo.

---

## 2.3. La señal de control: PWM de 50 Hz

La orden no se envía como un número: se envía como **el ancho de un pulso**. La convención de
la industria es:

```
Periodo:        20 ms  (frecuencia de 50 Hz)
Pulso:          1,0 ms  →  un extremo del recorrido (0°)
                1,5 ms  →  centro (90°)
                2,0 ms  →  el otro extremo (180°)
```

```
        |<-------------------- 20 ms -------------------->|
        ┌────┐                                            ┌────
        │    │                                            │
   ─────┘    └────────────────────────────────────────────┘
        |<->|
        ancho de pulso (1 a 2 ms)
```

Detalles que sí importan en el laboratorio:

- **No es el PWM de `analogWrite()`.** `analogWrite()` genera una onda de ~490 Hz con ciclo de
  trabajo proporcional; el servo espera pulsos de duración absoluta. Por eso se usa la
  librería, no `analogWrite()`.
- **La relación no es exactamente lineal ni universal.** Muchos servos aceptan 0,5–2,5 ms para
  recorrer algo más de 180°, y el rango real varía entre modelos. El documento del fabricante
  manda.
- **Hay banda muerta.** El SG90 declara unos 10 µs de banda muerta; con una escala nominal de
  1000 µs para 180° (≈5,6 µs por grado), eso equivale a casi 2° que el servo puede ignorar.
  Es una fuente de error que conviene mencionar en el experimento A.
- **La resolución útil es mecánica, no numérica.** Aunque se ordene un ángulo con decimales,
  el servo no los resuelve.

### Ficha típica del SG90

| Parámetro | Valor típico |
| --- | --- |
| Tensión de operación | 4,8 – 6,0 V |
| Velocidad | ≈0,1 s por 60° a 4,8 V |
| Par de bloqueo (*stall*) | ≈1,8 kg·cm a 4,8 V |
| Banda muerta | ≈10 µs |
| Peso | ≈9 g |

La velocidad es la que fija el techo físico del movimiento progresivo: un recorrido completo
de 180° tarda del orden de **0,3 s** al máximo. Cualquier "velocidad máxima configurable" del
firmware debe ser **menor** que eso, o el servo simplemente saturará y el perfil dejará de
ser controlable.

---

## 2.4. La librería `Servo.h`

### API mínima

| Método | Qué hace | Nota |
| --- | --- | --- |
| `attach(pin)` | Asocia un servo al pin y reserva un canal | Devuelve el número de canal, o 0 si falla |
| `attach(pin, min, max)` | Igual, con anchos de pulso en µs | Sirve para servos con recorrido extendido |
| `write(angulo)` | Ordena un ángulo entre 0 y 180 | **Satura** fuera de rango, no avisa |
| `writeMicroseconds(us)` | Ordena un ancho de pulso directo | Más fino; permite calibrar |
| `read()` | Devuelve **el último valor escrito** | **No mide la posición real** |
| `detach()` | Libera el canal y deja de generar pulsos | El servo deja de mantener posición |
| `attached()` | Indica si hay un servo asociado al pin | Útil para diagnósticos |

> **Punto crítico para el análisis.** `read()` es una copia de la orden, no una medición. Si
> el firmware reporta `read()`, está reportando el **ángulo ordenado**. Para reportar el ángulo
> **medido** haría falta un sensor externo (encoder, potenciómetro acoplado al eje, IMU,
> visión) o un servo que exponga su realimentación.

### Cómo genera los pulsos

En placas AVR la librería **no usa un canal PWM por servo**. Configura un temporizador de
16 bits para que interrumpa cada 20 ms y, dentro de la interrupción, va encendiendo y apagando
cada pin asociado en secuencia. Por eso puede manejar varios servos con un solo temporizador.
El código fuente lo deja ver: `src/avr/ServoTimers.h` define los temporizadores disponibles
según la placa y, para el caso general (Uno, Nano), solo habilita `Timer1`.

### Restricciones que hay que declarar en el informe

- **Servos simultáneos:** hasta **12** en la mayoría de placas y hasta **48** en el Mega.
- **PWM perdido:** en placas distintas del Mega, usar la librería **inhabilita
  `analogWrite()` en los pines 9 y 10**, haya o no un servo conectado a ellos. En el Mega, de
  12 a 23 servos afectan los pines 11 y 12.
- **Conflicto de temporizador:** cualquier otra librería que use `Timer1` (algunas de audio,
  de control de motores o de temporización) chocará con `Servo`. Si el proyecto crece, este es
  el primer sitio donde mirar.
- **Costo en CPU:** cada pulso se genera por interrupción; con varios servos y un ciclo
  principal ajustado, el tiempo de CPU deja de ser despreciable.

Estas restricciones no son un detalle académico: si se necesita PWM en el pin 9 para otra
cosa, hay que replanear el montaje o cambiar de placa.

---

## 2.5. Servo de posición frente a servo de rotación continua

| Aspecto | Posición (SG90) | Rotación continua (p. ej. FS90R) |
| --- | --- | --- |
| Variable de control | **Ángulo** objetivo | **Velocidad y sentido** de giro |
| Señal de 1,5 ms | Centro del recorrido (90°) | Detenido |
| Señal < 1,5 ms | Gira hacia un extremo | Gira en un sentido, más rápido cuanto más se aleja del centro |
| Señal > 1,5 ms | Gira hacia el otro extremo | Gira en el sentido opuesto |
| Realimentación de posición | Sí, potenciómetro interno | No; el potenciómetro se ajusta para que no haya lazo de posición |
| ¿Mantiene la posición? | Sí | No |
| ¿Sirve para este laboratorio? | **Sí** | **No**: no hay ángulo que reportar ni representar |

La distinción es relevante porque el enunciado pide un **ángulo** y un reporte `S:<angulo>`.
Con un servo de rotación continua no existe tal ángulo: solo se podría reportar una velocidad
ordenada, lo que rompe el protocolo y la situación asignada.

---

## 2.6. Aspectos eléctricos y mecánicos que arruinan prácticas

- **Consumo de arranque.** El SG90 puede pedir varios cientos de miliamperios al arrancar, más
  que lo que entrega con holgura un puerto USB. El síntoma clásico es **reinicio del Arduino**
  o movimiento errático. Solución del enunciado: fuente externa **con tierra común**.
- **Tierra común.** Sin la tierra compartida, la señal PWM no tiene referencia y el servo se
  comporta de forma aleatoria.
- **Tope mecánico.** Forzar el eje más allá del recorrido quema el motor o rompe engranajes de
  plástico. Los valores fuera de 0–180 deben descartarse **en el firmware**, no confiarse a que
  la librería los recorte.
- **Ruido en la alimentación.** El motor introduce ruido que también afecta la lectura del
  potenciómetro; conviene leer el potenciómetro varias veces o promediar.

---

## 2.7. Aplicación al laboratorio (situación 7)

- **Variable representada:** orientación de la antena del radar, mapeada desde el ángulo del
  servo. El grupo debe declarar el rango angular útil (por ejemplo, 0–180° o un subrango) y la
  relación con la orientación mostrada.
- **Velocidad máxima configurable:** el firmware debe acercarse al objetivo con un paso máximo
  por ciclo (por ejemplo, `max_grados_por_segundo`). Ese límite debe estar por debajo de la
  velocidad física del servo (~600 °/s en el SG90) para que el perfil se cumpla.
- **Reporte de ángulos intermedios:** como el movimiento es progresivo, el reporte periódico
  muestra valores intermedios. Eso es un requisito, no un efecto indeseado: evidencia que la
  representación sigue al actuador y no solo la orden final.
- **Restricción de pines:** si el montaje necesita `analogWrite()` en 9 o 10, hay que cambiar
  el pin del servo o la placa. Conviene documentarlo en la metodología.

---

## 2.8. Errores frecuentes

| Error | Consecuencia |
| --- | --- |
| Alimentar el servo del pin de 5 V del Arduino sin fuente externa | Reinicios y movimientos erráticos. |
| Reportar `read()` como si fuera el ángulo medido | El análisis de la pregunta 1 queda mal planteado. |
| Usar `analogWrite()` para "mover el servo" | El servo vibra o no responde; no es la señal correcta. |
| No validar 0–180 antes de `write()` | La librería satura en silencio; el reporte miente. |
| Ignorar el conflicto de `Timer1` | Una librería deja de funcionar sin mensaje de error. |
| Prometer precisión de décimas de grado | La banda muerta y la mecánica no lo permiten. |

---

## 2.9. Preguntas de autoevaluación

1. ¿Por qué el servo mantiene la posición si se le aplica una carga externa?
2. Con 20 ms de periodo, ¿qué porcentaje del tiempo está el pulso en alto en el centro?
3. ¿Qué devuelve `Servo.read()` y por qué no sirve como medición?
4. ¿Qué recurso del microcontrolador consume `Servo.h` y qué otra función inhabilita en un
   Arduino Uno?
5. Si se pide un ángulo de 200°, ¿qué hace `write()` y qué debería hacer el firmware?
6. ¿Por qué un servo de rotación continua no permite cumplir el protocolo del laboratorio?

---

## 2.10. Fuentes consultadas

1. **Arduino.** *Servo library — Reference.*
   <https://docs.arduino.cc/libraries/servo/>
   → Documentación oficial de la API y de las restricciones de la librería (número de servos,
   pines PWM afectados, temporizadores).

2. **Arduino.** *Basic servo control.*
   <https://docs.arduino.cc/learn/electronics/servo-motors/>
   → Montaje, alimentación y ejemplo mínimo de `attach()` / `write()`.

3. **Arduino.** *Secrets of Arduino PWM.*
   <https://docs.arduino.cc/tutorials/generic/secrets-of-arduino-pwm/>
   → Explica qué temporizadores controlan qué pines y por qué el PWM de hardware no es la
   señal de un servo.

4. **ServoCity.** *How Does a Servo Work?*
   <https://www.servocity.com/how-does-a-servo-work/>
   → Diagrama interno, lazo de control y relación entre ancho de pulso y posición.

5. **Pololu.** *Servo Motor Documentation.*
   <https://www.pololu.com/docs/0J19/all>
   → Diferencias entre servos de posición y de rotación continua; rangos de pulso y calibración.

6. **TowerPro.** *SG90 9 g Micro Servo.*
   <https://www.towerpro.com.tw/product/sg90-7/>
   → Ficha del servo usado en el montaje (tensión, velocidad, par, banda muerta).

7. **Arduino Libraries.** *Servo — código fuente, `src/avr/ServoTimers.h`.*
   <https://github.com/arduino-libraries/Servo/blob/master/src/avr/ServoTimers.h>
   → Evidencia de que en el caso general (Uno/Nano) la librería usa `Timer1`.

---

**Anterior:** [Gemelos digitales](./01-gemelos-digitales.md) ·
**Siguiente:** [Programación no bloqueante](./03-programacion-no-bloqueante.md)
