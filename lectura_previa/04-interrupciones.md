# 4. Interrupciones en el microcontrolador

**Guía de lectura del pre-laboratorio** · Tema 4 del enunciado
**Tiempo estimado:** 45–60 min · **Fuentes al final del documento**

---

## 4.1. Qué debe quedar claro

Este tema es **opcional** en la implementación: el enunciado dice que su uso "depende del
diseño de cada grupo". Pero la fundamentación es obligatoria, y hay una decisión que debe
justificarse: **¿se usa interrupción o consulta periódica, y por qué?**

Al terminar debe poder explicar:

1. Qué es una interrupción y qué ocurre en el microcontrolador cuando llega.
2. Cómo se configura con `attachInterrupt()` y qué modos existen.
3. Qué restricciones tiene el código que corre dentro de una interrupción.
4. Cuándo conviene una interrupción y cuándo basta con consultar una bandera en el ciclo
   principal.

---

## 4.2. Qué es una interrupción

Una interrupción es un **evento que suspende el flujo normal del programa**, guarda el estado
mínimo necesario, ejecuta una función especial (la rutina de servicio, *ISR*) y devuelve el
control exactamente donde estaba. El programa principal no sabe que ocurrió: no hay una
llamada en el código que la origine.

Fuentes típicas en un Arduino:

| Fuente | Ejemplo en este laboratorio |
| --- | --- |
| Externas por pin | Un pulsador, un encoder, un sensor de paso |
| Temporizador | Base de tiempo de `millis()`; generación de los pulsos del servo |
| Puerto serial (USART) | Cada byte que llega se guarda en el búfer por interrupción |
| Conversor analógico-digital | Fin de conversión (usado internamente por `analogRead`) |

El microcontrolador tiene una **tabla de vectores**: una dirección fija por cada fuente. Al
producirse el evento, el hardware consulta la tabla y salta. Por eso las ISR se declaran con
nombres reservados (`INT0_vect`, `TIMER1_OVF_vect`, …) o mediante la macro `ISR()` de
`avr/interrupt.h`.

### Latencia

La latencia es el tiempo entre el evento y la primera instrucción de la ISR. En un AVR a
16 MHz es del orden de **unos pocos microsegundos**, y depende de:

- Si las interrupciones están habilitadas en ese instante (dentro de otra ISR, no lo están).
- La instrucción en curso (algunas instrucciones de varias palabras tardan más en terminar).
- La prioridad, cuando hay varias fuentes pendientes.

Es la razón por la que una interrupción existe: **acotar la latencia**. Un `loop()` que tarda
20 ms puede detectar un evento con 20 ms de retraso; una interrupción, en microsegundos.

---

## 4.3. Configuración con `attachInterrupt()`

```cpp
const byte PIN_EVENTO = 2;          // en Uno/Nano: pines 2 y 3 (INT0, INT1)
volatile bool evento_pendiente = false;

void alDetectarEvento() {
  evento_pendiente = true;          // trabajo mínimo
}

void setup() {
  pinMode(PIN_EVENTO, INPUT_PULLUP);
  attachInterrupt(digitalPinToInterrupt(PIN_EVENTO), alDetectarEvento, FALLING);
}
```

| Modo | Se dispara cuando el pin… |
| --- | --- |
| `RISING` | pasa de bajo a alto |
| `FALLING` | pasa de alto a bajo |
| `CHANGE` | cambia en cualquier sentido |
| `LOW` | está en bajo (nivel, no flanco; disponible según la placa) |

Puntos prácticos:

- `digitalPinToInterrupt(pin)` traduce el número de pin al número de interrupción. Usar el
  número "a mano" (`attachInterrupt(0, …)`) es frágil: depende de la placa.
- En Arduino Uno y Nano solo los pines **2 y 3** tienen interrupción externa dedicada. Otras
  placas ofrecen más, y en algunas **todos** los pines pueden generar interrupción por cambio
  de estado (*pin change interrupt*), aunque con más latencia y complejidad.
- `detachInterrupt(pin)` desactiva la interrupción.
- Si el evento es un pulsador mecánico, el rebote puede generar decenas de interrupciones. Se
  resuelve **registrando la marca de tiempo en la ISR** y filtrando en el ciclo principal, no
  con `delay()` dentro de la ISR.

> **Nota sobre el ejemplo:** en AVR no se necesitan atributos especiales para la ISR. En placas
> ESP32 sí se usa `IRAM_ATTR` y el registro es distinto. Este laboratorio trabaja con Arduino
> AVR, así que el ejemplo corresponde al montaje; si el grupo usa otra placa, debe adaptarlo y
> decirlo.

---

## 4.4. Restricciones del código que corre dentro de una ISR

Aquí está el 90 % de los errores. Al entrar en una ISR, el hardware **deshabilita las
interrupciones globales**. Mientras la ISR se ejecute, no se atiende ninguna otra fuente.

| Restricción | Motivo | Qué hacer en su lugar |
| --- | --- | --- |
| **Debe ser corta** (decenas de µs) | Todo lo demás espera; se pierden eventos y se retrasa el servo | Solo leer, guardar una bandera o un valor, y salir |
| **No usar `delay()`** | Se queda esperando un contador que no avanza: se cuelga | Temporizar en el ciclo principal |
| **No confiar en `millis()` / `micros()`** | No avanzan mientras la ISR tiene las interrupciones deshabilitadas | Guardar el valor *antes* o usar un contador propio |
| **No usar `Serial`** | La transmisión y la recepción dependen de interrupciones; `print()` puede bloquearse | Guardar el dato y enviarlo desde el ciclo principal |
| **Variables compartidas: `volatile`** | El compilador podría cachear el valor en un registro | `volatile uint8_t bandera;` |
| **Acceso atómico a datos de más de 8 bits** | Una lectura de 16 bits son dos instrucciones; la ISR puede cambiar el valor entre ellas | `noInterrupts()` / `interrupts()` alrededor de la lectura, o `ATOMIC_BLOCK` |
| **Sin asignación dinámica** | `malloc`/`free` no son seguros en ese contexto y consumen pila | Búferes estáticos |
| **Pila compartida** | La ISR usa la misma pila que el programa principal | Evitar variables locales grandes y llamadas profundas |

Ejemplo del problema de atomicidad:

```cpp
volatile uint16_t pulsos = 0;      // la ISR lo incrementa

void loop() {
  uint16_t copia;
  noInterrupts();
  copia = pulsos;                  // lectura atómica
  interrupts();
  // usar copia
}
```

Sin ese bloqueo, el programa podría leer la mitad alta del valor viejo y la mitad baja del
nuevo: un número imposible.

---

## 4.5. Interrupción o consulta periódica

No hay una respuesta única; hay criterios.

| Criterio | Favorece la interrupción | Favorece la consulta |
| --- | --- | --- |
| Duración del evento | Más corto que el periodo del ciclo (pulsos de encoder) | Más largo que el ciclo (estado de un potenciómetro) |
| Consecuencia de perderlo | Se pierde información (conteo, flanco) | Se recupera en la siguiente vuelta |
| Latencia necesaria | Acotada y pequeña | Flexible |
| Complejidad | Aceptable si la ISR es trivial | Preferible si el procesamiento es elaborado |
| Riesgo de conflicto | Temporizadores, librerías, pines | Ninguno |

La regla práctica: **la ISR detecta, el ciclo principal procesa**. Todo lo que sea cálculo,
formato de texto, filtrado o envío de datos va fuera de la ISR.

---

## 4.6. Qué pasa en este laboratorio en particular

Tres observaciones que conviene poner en el informe, porque demuestran criterio:

1. **La lectura del potenciómetro no necesita interrupción.** `analogRead()` tarda del orden
   de 0,1 ms y el estado del potenciómetro cambia lentamente. Consultarlo cada 20 ms es
   suficiente y más simple.
2. **La recepción serial ya es por interrupción, aunque no se llame a `attachInterrupt()`.**
   El módulo USART llena un búfer de 64 bytes por interrupción. Consultar `Serial.available()`
   en el ciclo principal **no** es "consultar el hardware a ciegas": es leer un búfer que se
   llena solo. Por eso no hace falta una interrupción externa para el protocolo.
3. **Cuidado con los temporizadores.** La librería `Servo` ya ocupa `Timer1` en el Uno/Nano.
   Un temporizador propio configurado sobre `Timer1` **rompería los pulsos del servo**. Si se
   quiere una base de tiempo por interrupción, hay que usar otro temporizador (`Timer2`) o,
   mejor, `millis()`.

### Usos razonables en este proyecto

| Uso | ¿Vale la pena? |
| --- | --- |
| Encoder o pulsador adicional para un mando local | Sí, si el rebote se filtra fuera de la ISR |
| Contar pulsos de un sensor de paso | Sí: se perderían entre ciclos |
| Generar el periodo de reporte | No: `millis()` es suficiente y no compite por temporizadores |
| Leer el potenciómetro | No: la consulta periódica es adecuada |
| Recibir los comandos `A:` | No: el búfer serial ya es por interrupción |

Si el grupo decide **no** usar interrupciones, la justificación es exactamente esta tabla. Si
decide usarlas, debe señalar para qué y demostrar que la ISR es breve.

---

## 4.7. Errores frecuentes

| Error | Síntoma |
| --- | --- |
| `Serial.print()` dentro de la ISR | Cuelgues intermitentes o pérdida de datos |
| `delay()` dentro de la ISR | El programa se detiene por completo |
| Variable compartida sin `volatile` | El ciclo principal "no ve" el cambio |
| Contador de 16 bits leído sin bloqueo atómico | Valores absurdos esporádicos |
| ISR que hace filtrado, promedios o formateo | Latencia alta, servo entrecortado |
| Interrupción sobre un pulsador sin antirrebote | Decenas de eventos por pulsación |
| Temporizador propio sobre `Timer1` con `Servo` activo | El servo vibra o no responde |

---

## 4.8. Preguntas de autoevaluación

1. ¿Por qué `millis()` no avanza dentro de una ISR?
2. ¿Por qué una variable compartida con una ISR debe declararse `volatile`? ¿Basta con eso
   cuando la variable es de 16 bits?
3. Explique la frase "la ISR detecta, el ciclo principal procesa" con un ejemplo del proyecto.
4. Si el puerto serial ya usa interrupciones internamente, ¿qué aporta `attachInterrupt()`?
5. ¿Qué conflicto aparece si se configura `Timer1` para el periodo de reporte?
6. ¿En qué caso del montaje una consulta periódica perdería información?

---

## 4.9. Fuentes consultadas

1. **Arduino.** *`attachInterrupt()` — Language Reference.*
   <https://docs.arduino.cc/language-reference/en/functions/external-interrupts/attachInterrupt/>
   → Firma, modos, pines disponibles por placa y advertencia de mantener la ISR corta.

2. **Gammon, N.** *Interrupts.*
   <https://gammon.com.au/interrupts>
   → Referencia técnica muy detallada sobre interrupciones en AVR: vectores, latencia,
   `volatile`, atomicidad y errores típicos.

3. **avr-libc.** *Interrupts and Signals* (documentación de `avr/interrupt.h`).
   <https://www.nongnu.org/avr-libc/user-manual/group__avr__interrupts.html>
   → Macro `ISR()`, `sei()`/`cli()`, `ATOMIC_BLOCK` y semántica del compilador.

4. **Microchip.** *ATmega328P Datasheet* (sección *Interrupts*).
   <https://ww1.microchip.com/downloads/en/DeviceDoc/ATmega48A-PA-88A-PA-168A-PA-328-P-DS-DS40002061A.pdf>
   → Fuente primaria: tabla de vectores, banderas de interrupción y temporizadores.

5. **Gammon, N.** *Arduino Timers.*
   <https://gammon.com.au/timers>
   → Qué temporizador usa cada recurso del Arduino y cómo detectar conflictos con librerías
   como `Servo`.

> **Nota sobre el uso de IA en la redacción.** Si se usó asistencia automatizada para redactar
> esta guía, conviene declararlo en el informe y verificar cada afirmación contra las fuentes
> primarias. Las cifras de esta guía (latencia, 0,1 ms por `analogRead`, 64 bytes de búfer)
> dependen de la placa y deben confirmarse en el montaje.

---

**Anterior:** [Programación no bloqueante](./03-programacion-no-bloqueante.md) ·
**Siguiente:** [Comunicación serial bidireccional](./05-comunicacion-serial-bidireccional.md)
