# 3. Programación no bloqueante con `millis()`

**Guía de lectura del pre-laboratorio** · Tema 3 del enunciado
**Tiempo estimado:** 60–80 min · **Fuentes al final del documento**

---

## 3.1. El problema que resuelve

El firmware de este laboratorio tiene que hacer **tres cosas a la vez**, todo el tiempo:

1. Leer el potenciómetro y decidir el ángulo objetivo.
2. Mover el servomotor hacia ese objetivo **de forma progresiva**.
3. Reportar el estado por el puerto serial con un periodo definido.

Además, en cualquier momento puede llegar un comando `A:` que hay que atender. Un programa
escrito con `delay()` no puede sostener eso: mientras espera, **no lee, no mueve y no atiende
el puerto**. La pregunta del pre-laboratorio es, entonces, cómo ejecutar tareas periódicas sin
detener el flujo del programa.

Al terminar debe poder escribir, de memoria, el patrón de temporización con `millis()` y
explicar por qué funciona incluso cuando el contador se desborda.

---

## 3.2. Qué hace realmente `delay()`

```cpp
delay(500);   // "espera 500 ms"
```

En AVR, `delay()` **no apaga el microcontrolador**: ejecuta un ciclo cerrado que consulta
`millis()` hasta que ha pasado el tiempo pedido. Las interrupciones siguen habilitadas, así que
el conteo de milisegundos avanza y el puerto serial sigue recibiendo bytes en su memoria
intermedia. Lo que se detiene es **el código del programa**: no se ejecuta la siguiente línea.

| Sigue ocurriendo durante `delay()` | Se detiene durante `delay()` |
| --- | --- |
| Conteo de `millis()` y `micros()` | Lectura del potenciómetro |
| Recepción serial (llenado del búfer) | Actualización del ángulo objetivo |
| Pulsos del servo (por interrupción de temporizador) | Movimiento progresivo |
| | Envío de reportes nuevos |

Consecuencias típicas en este laboratorio: el servo se queda quieto, el comando `A:` que
llegó durante la espera se procesa tarde, y el periodo de reporte deja de ser el declarado
(se vuelve `periodo + delay`). Por eso el enunciado prohíbe `delay()` en el ciclo principal.

> **Matiz que suele confundirse:** `Servo.write()` **no** bloquea. Solo fija el ancho de pulso
> objetivo; el servo se mueve a su propia velocidad. El bloqueo está en la espera del
> programador, no en la orden.

---

## 3.3. `millis()`: qué es y qué límites tiene

`millis()` devuelve un `unsigned long` con los milisegundos transcurridos desde el arranque.
En AVR es un contador de 32 bits incrementado por una interrupción de temporizador.

| Propiedad | Valor |
| --- | --- |
| Tipo | `unsigned long` (32 bits en AVR) |
| Resolución | 1 ms |
| Desbordamiento | 2³² ms ≈ **49,7 días** |
| Qué pasa al desbordar | Vuelve a 0 (no es un error, es aritmética modular) |

`micros()` tiene el mismo problema con un periodo mucho más corto: 2³² µs ≈ **71,6 minutos**.

El desbordamiento parece un detalle teórico hasta que el montaje queda encendido varios días
en una feria o una demostración. La forma correcta de temporizar no depende de que el contador
nunca dé la vuelta.

---

## 3.4. El patrón correcto

```cpp
const unsigned long PERIODO_REPORTE_MS = 200;
unsigned long ultimo_reporte = 0;

void loop() {
  unsigned long ahora = millis();

  if (ahora - ultimo_reporte >= PERIODO_REPORTE_MS) {
    ultimo_reporte = ahora;
    enviarReporte();
  }
}
```

Por qué funciona: la resta de dos `unsigned long` se calcula **módulo 2³²**. Si `ahora` ya
dio la vuelta y vale, por ejemplo, 30, mientras `ultimo_reporte` vale 4 294 967 000, la resta
da 326, que es exactamente el tiempo transcurrido. La comparación es correcta a ambos lados
del desbordamiento.

### La versión que falla

```cpp
// MAL: deja de funcionar justo cuando millis() se desborda
if (millis() > ultimo_reporte + PERIODO_REPORTE_MS) { ... }
```

Al desbordar, `ultimo_reporte + PERIODO` se vuelve pequeño y la condición puede quedar
permanentemente falsa (o verdadera) durante días. También falla si se guarda el tiempo en un
`int` de 16 bits: 32 767 ms son apenas 32 segundos.

---

## 3.5. De "una tarea" a "varias tareas"

El patrón se repite por tarea. Dos formas habituales:

### a) Una marca de tiempo por tarea

```cpp
if (ahora - ultimo_muestreo >= PERIODO_MUESTREO_MS) { ultimo_muestreo = ahora; muestrear(); }
if (ahora - ultimo_paso     >= PERIODO_PASO_MS)     { ultimo_paso     = ahora; avanzarServo(); }
if (ahora - ultimo_reporte  >= PERIODO_REPORTE_MS)  { ultimo_reporte  = ahora; reportar(); }
```

Es simple y suficiente para tres tareas. Tiene un defecto: cada tarea **arrastra su propio
retraso**. Si el ciclo tarda 3 ms y el periodo es 10 ms, el periodo real será de 12 ms y el
error se acumula ligeramente.

### b) Próximo vencimiento por tarea

```cpp
struct Tarea { unsigned long periodo; unsigned long proximo; void (*fn)(); };

Tarea tareas[] = {
  {  20, 0, muestrearPot },
  {  20, 0, avanzarServo },
  { 200, 0, reportar     },
};

void loop() {
  unsigned long ahora = millis();
  for (auto &t : tareas) {
    if ((long)(ahora - t.proximo) >= 0) {
      t.proximo += t.periodo;   // se suma al vencimiento, no a "ahora"
      t.fn();
    }
  }
}
```

Sumar al **vencimiento anterior** mantiene el periodo promedio exacto aunque el ciclo se
retrase, y evita la acumulación de error. Es la misma idea que usa un planificador cooperativo.

### Advertencia sobre el tiempo de ciclo

En un esquema cooperativo, **una tarea larga retrasa a todas las demás**. Si una función tarda
más que el periodo más corto, el sistema no cumple. Hay que medir el tiempo de ciclo
(`loop()` de principio a fin) y dejarlo cómodamente por debajo del periodo mínimo elegido.

---

## 3.6. Movimiento progresivo: un integrador con límite de velocidad

"Mover el servo progresivamente" significa que la orden no salta al objetivo: se acerca en
pasos acotados. Es un **limitador de velocidad** (en inglés, *slew rate limiter*), calculado
con el tiempo real transcurrido, no con un contador de iteraciones:

```cpp
const float VEL_MAX_DEG_S = 120.0f;   // configurable
float angulo_actual = 90.0f;
float angulo_objetivo = 90.0f;
unsigned long t_prev = 0;

void avanzarServo() {
  unsigned long ahora = millis();
  float dt = (ahora - t_prev) / 1000.0f;
  t_prev = ahora;

  float paso_max = VEL_MAX_DEG_S * dt;
  float error = angulo_objetivo - angulo_actual;

  if (fabs(error) <= paso_max) {
    angulo_actual = angulo_objetivo;        // llega y se queda
  } else {
    angulo_actual += (error > 0 ? paso_max : -paso_max);
  }

  servo.write((int)round(angulo_actual));
}
```

Detalles que evaluará la rúbrica:

- `VEL_MAX_DEG_S` debe ser **configurable** y estar por debajo de la velocidad física del servo
  (~600 °/s en un SG90). Si se pone por encima, el perfil no se cumple y el movimiento vuelve a
  ser un salto.
- Usar `dt` real (no "un paso cada 20 ms") hace que el movimiento sea correcto aunque el ciclo
  se retrase.
- El redondeo a entero es inevitable porque `write()` recibe un ángulo entero; conviene
  mantener el estado interno en `float` para no perder resolución.
- El reporte debe enviar el **ángulo actual** (el que se está ordenando en ese instante), no el
  objetivo, para que se vean los valores intermedios.

---

## 3.7. Bloqueos invisibles: `delay()` no es el único

Un programa puede ser no bloqueante "en apariencia" y bloquearse en otra parte. En este
laboratorio hay que revisar:

| Llamada | Bloquea hasta | Alternativa |
| --- | --- | --- |
| `delay(ms)` | El tiempo indicado | `millis()` + bandera |
| `Serial.readStringUntil('\n')` | Que llegue el delimitador o **1 s** (timeout por defecto) | `Serial.available()` + búfer propio |
| `Serial.parseInt()` | Que termine el número o 1 s | Parser propio sobre la línea completa |
| `Serial.print()` con el búfer lleno | Que se libere espacio en TX (64 bytes en AVR) | Enviar mensajes cortos y con periodo holgado |
| `while (!Serial);` | Indefinidamente si no hay monitor | Solo en placas con USB nativo, con cuidado |
| Librerías con `delay()` interno | Variable | Revisar el código o cambiar de librería |

El caso de `readStringUntil` es el más traicionero: **parece** una lectura por línea y en
realidad puede congelar el ciclo un segundo entero. Con un periodo de reporte de 200 ms, eso
son cinco periodos perdidos.

---

## 3.8. Presupuesto de tiempo para este laboratorio

Un ejemplo de dimensionamiento que el grupo debe ajustar y **justificar**:

| Tarea | Periodo propuesto | Costo aproximado | Por qué |
| --- | --- | --- | --- |
| Leer potenciómetro (`analogRead`) | 20 ms | ~0,1 ms (una conversión ADC) | Suficiente para seguir la mano; el ruido se filtra |
| Avanzar el servo | 20 ms | despreciable | Pasos suaves de ~2,4° a 120 °/s |
| Atender serial | cada vuelta del `loop()` | despreciable | El búfer de recepción ya se llena por interrupción |
| Reportar estado | 200 ms | ~10,4 ms de transmisión a 9600 baudios | 5 reportes por segundo, sin saturar el enlace |

Cuentas que hay que poder defender:

- A 9600 baudios con 8N1 se transmiten **960 bytes/s**, es decir **~1,04 ms por byte**.
- `S:180,POT\n` son 10 bytes → **~10,4 ms** de transmisión.
- Con periodo de 200 ms, el enlace queda ocupado ~5 % del tiempo en ese sentido.
- A 20 ms de paso, el servo avanza como máximo ~2,4° por paso a 120 °/s: el ojo ve un
  movimiento continuo, no una escalera.

Si se elige un periodo más corto, hay que demostrar que el enlace y el ciclo aguantan; si se
elige más largo, hay que explicar por qué la representación puede permitirse ese retraso.

---

## 3.9. Errores frecuentes

| Error | Efecto |
| --- | --- |
| `delay()` "pequeño" dentro del ciclo | Ya rompe el requisito y desfasa el periodo. |
| Comparar con `>` y sumar al "ahora" | Deriva del periodo y fallo al desbordar. |
| Guardar tiempos en `int` | Falla a los 32 s. |
| Leer el potenciómetro cada vuelta del `loop()` sin periodo | Ruido y carga innecesaria. |
| Mover el servo con un contador de vueltas | La velocidad depende de la carga del ciclo. |
| Reportar el objetivo en vez del ángulo actual | Se pierden los valores intermedios que exige el enunciado. |

---

## 3.10. Preguntas de autoevaluación

1. ¿Por qué `delay()` impide cumplir el requisito de "leer entradas mientras actúa", si las
   interrupciones siguen activas?
2. Escriba de memoria la condición de temporización con `millis()` y explique por qué no falla
   al desbordar.
3. ¿Qué diferencia hay entre "un paso cada 20 ms" y "avanzar `velocidad × dt`"?
4. ¿Por qué `Serial.readStringUntil()` es una forma de bloqueo?
5. Con 9600 baudios, ¿cuánto tarda un reporte de 10 bytes y cuántos caben por segundo?
6. ¿Qué evidencia experimental demostraría que el ciclo principal no se bloquea?

---

## 3.11. Fuentes consultadas

1. **Arduino.** *`millis()` — Language Reference.*
   <https://docs.arduino.cc/language-reference/en/functions/time/millis/>
   → Tipo de retorno, resolución y nota sobre el desbordamiento (≈50 días).

2. **Arduino.** *Blink Without Delay.*
   <https://docs.arduino.cc/built-in-examples/digital/BlinkWithoutDelay/>
   → Ejemplo canónico del patrón de temporización con `millis()`, con la comparación por resta.

3. **Adafruit.** *Multi-tasking the Arduino — Part 1.*
   <https://learn.adafruit.com/multi-tasking-the-arduino-part-1>
   → Cómo pasar de `delay()` a varias tareas periódicas; explica por qué el enfoque escala mal.

4. **Adafruit.** *Multi-tasking the Arduino — Part 2.*
   <https://learn.adafruit.com/multi-tasking-the-arduino-part-2>
   → Máquinas de estados y planificación cooperativa sin sistema operativo.

5. **Arduino.** *`micros()` — Language Reference.*
   <https://docs.arduino.cc/language-reference/en/functions/time/micros/>
   → Mismo problema de desbordamiento con periodo corto (≈70 minutos).

6. **Arduino.** *`Serial.setTimeout()` — Language Reference.*
   <https://docs.arduino.cc/language-reference/en/functions/communication/serial/setTimeout/>
   → Documenta el tiempo de espera por defecto (1000 ms) que hace bloqueantes a
   `readStringUntil()` y `parseInt()`.

---

**Anterior:** [Servomotores](./02-servomotores.md) ·
**Siguiente:** [Interrupciones](./04-interrupciones.md)
