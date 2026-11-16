# Laboratorio de clase — Gemelo digital con servomotor

**Asignatura:** Laboratorio de clase (Realidad Mixta)
**Facultad de Ingeniería — Universidad de San Buenaventura, Bogotá**
**Enunciado:** Ing. Sergio Alberto Reyes Gómez
**Situación asignada: N.° 7 — Radar de vigilancia**

---

## Descripción

El laboratorio consiste en construir un **gemelo digital** de un sistema físico sencillo: un
servomotor de posición controlado localmente por un potenciómetro y conectado por puerto
serial a una escena de **Godot 4**. El sistema debe funcionar en los **dos sentidos**:

- el **mando físico** (potenciómetro) mueve el servo y la escena se actualiza sola;
- el **mando digital** (control en la escena) mueve el servo y el firmware reporta el nuevo estado.

Como ambos mandos pueden actuar a la vez, cada grupo debe diseñar una **política de
arbitraje** que defina cuál prevalece y cómo se trata el ruido del potenciómetro. Después se
mide experimentalmente el **error angular** y la **coherencia de estado** entre los dos lados.

El entregable no es solo un montaje que funciona: es un sistema cuya clasificación como
gemelo digital se sostiene con un marco teórico, una política justificada y datos propios.

> **Nota sobre la plataforma.** El enunciado menciona Unity. El grupo implementa la
> representación digital en **Godot 4** con el addon **GdSerial** para el enlace serial, porque
> esa combinación ya se usó con éxito en el proyecto anterior del curso. El protocolo, los
> requisitos y los entregables no cambian; conviene dejar la decisión explícita en el informe y
> en el póster.

---

## Situación 7: radar de vigilancia

| Aspecto | Definición |
| --- | --- |
| Variable controlada por el ángulo | Orientación de la antena del radar |
| Comportamiento a simular | Pantalla de radar con objetos en movimiento que **solo se detectan** cuando la antena apunta hacia ellos |
| Mando físico | Potenciómetro |
| Mando digital | Control en la escena de Godot |
| Rango útil | *Definir por el grupo* (0–180° o un subrango justificado) |

La escena no puede limitarse a girar un objeto: debe mostrar el barrido, los blancos en
movimiento y la lógica de detección, de modo que la situación se reconozca sin explicación.

---

## Estructura del repositorio

```
.
├── README.md                 Este documento
├── enunciado.md              Enunciado oficial del laboratorio
├── rubrica.md                Criterios de evaluación
├── lectura_previa/           Guías de lectura del pre-laboratorio
│   ├── 01-gemelos-digitales.md
│   ├── 02-servomotores.md
│   ├── 03-programacion-no-bloqueante.md
│   ├── 04-interrupciones.md
│   └── 05-comunicacion-serial-bidireccional.md
├── platformio.ini            Configuración de PlatformIO (Nano, bootloader 57600)
├── src/main.cpp              Firmware del Arduino (A0 potenciómetro, D4 servo)
└── game/                     Proyecto de Godot
    └── addons/gdserial/      Addon de comunicación serial (MIT)
```

> **Estado actual:** el firmware ya implementa el mando físico, el movimiento progresivo, el
> protocolo serial y la política de arbitraje. La escena de Godot está en desarrollo.

---

## Pre-laboratorio: guías de lectura

Cada tema del enunciado tiene su propio documento, pensado como guía de estudio: explica los
conceptos, los conecta con la situación 7, advierte los errores frecuentes y termina con
preguntas de autoevaluación y **fuentes enlazadas y comentadas**.

| # | Tema | Guía | Qué resuelve |
| --- | --- | --- | --- |
| 1 | Gemelos digitales | [01-gemelos-digitales.md](./lectura_previa/01-gemelos-digitales.md) | Diferencia entre modelo, sombra y gemelo digital según el intercambio de datos |
| 2 | Servomotores | [02-servomotores.md](./lectura_previa/02-servomotores.md) | Funcionamiento interno, PWM de control, `Servo.h` y sus restricciones de temporizadores |
| 3 | Programación no bloqueante | [03-programacion-no-bloqueante.md](./lectura_previa/03-programacion-no-bloqueante.md) | `millis()` frente a `delay()`, tareas periódicas y bloqueos invisibles |
| 4 | Interrupciones | [04-interrupciones.md](./lectura_previa/04-interrupciones.md) | `attachInterrupt()`, restricciones de las ISR y cuándo preferirlas sobre la consulta |
| 5 | Comunicación serial bidireccional | [05-comunicacion-serial-bidireccional.md](./lectura_previa/05-comunicacion-serial-bidireccional.md) | Delimitación de mensajes, parser sin bloqueo y lectura no bloqueante en Godot con GdSerial |

**Cómo usar las guías:** leer una, responder las preguntas de autoevaluación sin mirar el
texto y recién después revisar las fuentes originales. El marco teórico del póster debe salir
de esas fuentes, no de las guías: las guías son un mapa, no la cita.

---

## Arquitectura del sistema

```
                         A:<angulo>\n        
┌───────────────┐                            ┌───────────────┐
│     Godot     │ ─────────────────────────► │    Arduino    │
│  escena + UI  │                            │     + SG90    │
│               │ ◄────────────────────────  │     + pot.    │
└───────────────┘                            └───────────────┘
                    S:<angulo>,<fuente>\n    
                                                     │
                                                     ▲ mando físico
                                                 potenciómetro
```

### Protocolo de comunicación

Texto plano, **9600 baudios**, terminado en salto de línea (`\n`):

| Sentido | Formato | Función |
| --- | --- | --- |
| Godot → Arduino | `A:<angulo>` | Comando digital; entero entre 0 y 180 |
| Arduino → Godot | `S:<angulo>,<fuente>` | Reporte de estado; `<fuente>` es `POT` (mando físico) o `DIG` (mando digital) |

Reglas que el firmware debe cumplir: los valores fuera de rango y los mensajes mal formados se
**descartan sin afectar el funcionamiento**, y los reportes reflejan los **ángulos intermedios**
del movimiento progresivo, no solo el objetivo.

### Enlace serial en Godot: GdSerial

El puerto serial se maneja con el addon **[GdSerial](https://github.com/SujithChristopher/gdserial)**
(Rust sobre GDExtension, licencia MIT, Godot 4.4+), el mismo que se usó en el proyecto anterior
del curso. Ofrece dos clases:

| Clase | Modelo | Lectura no bloqueante |
| --- | --- | --- |
| `GdSerial` | Síncrona, un puerto | **Sí, con sondeo**: `bytes_available()` + `read()`, nunca `readline()` en `_process` |
| `GdSerialManager` | Asíncrona, hilos + señales | **Sí, por diseño**: el hilo lector hace la E/S y `poll_events()` entrega en el hilo principal |

El punto fino, que está desarrollado en la
[guía 5](./lectura_previa/05-comunicacion-serial-bidireccional.md#58-permite-gdserial-lecturas-no-bloqueantes),
es que `GdSerial.read()` **sí puede bloquear** hasta el timeout configurado (1000 ms por
defecto) si se llama sin datos. La lectura solo es no bloqueante cuando se consulta antes
`bytes_available()` y se configura `set_timeout(0)`.

---

## Requisitos por componente

### Firmware (Arduino)

| Elemento | Valor |
| --- | --- |
| Placa | Arduino Nano (ATmega328P, 5 V / 16 MHz) |
| Potenciómetro | `A0` |
| Servomotor | `D4` |
| Periodo de control | 20 ms (50 Hz) |
| Periodo de reporte | 100 ms (10 Hz) |
| Velocidad máxima de giro | 360 °/s (configurable) |
| Promedio de lectura | 8 muestras del ADC por ciclo |
| Umbral de seguimiento (mando físico) | 1° |
| Histéresis de retoma (desde mando digital) | 5°, sostenidos 3 ciclos (60 ms) |

> **Montaje mínimo:** potenciómetro entre 5 V y GND con el cursor en `A0`; servo con la señal
> en `D4` y alimentación estable (fuente externa con tierra común si el servo reinicia la
> placa). El rango útil se calibra con `POT_ADC_MIN` / `POT_ADC_MAX` en el firmware. En el
> Nano, `Servo` ocupa el Timer1: `analogWrite()` deja de funcionar en `D9` y `D10`.

Política de arbitraje implementada: **último mando que actúa gana, con histéresis y
confirmación temporal**. Un comando `A:` válido fija el objetivo y la fuente `DIG`; el
potenciómetro retoma el mando cuando se aparta **5° o más** de la posición que tenía al llegar
el comando **y** se mantiene así **3 ciclos seguidos** (60 ms).

Por qué esos valores:

| Parámetro | Razón |
| --- | --- |
| Umbral de seguimiento 2° | Con 1° el servo corrige ante cualquier variación de la lectura y el conjunto entra en una oscilación de ±4,5° con el potenciómetro quieto; con 2° el servo queda quieto. |
| Promedio de 8 muestras | Reduce el ruido aleatorio del ADC y cuesta ~0,9 ms por ciclo de 20 ms. |
| Histéresis de retoma 5° + 3 ciclos | Un pico aislado del ADC no puede anular el mando digital; un giro deliberado del potenciómetro supera ambos umbrales en 60 ms. |

Los tres umbrales se validaron en el montaje con comandos `A:` y giros del potenciómetro. Si se
cambia el potenciómetro o el cableado, conviene repetir la comprobación: con 1° de umbral la
oscilación aparece de inmediato y es fácil de detectar.

- [x] El potenciómetro controla el ángulo del servomotor.
- [x] Los comandos `A:` se aplican; los inválidos se descartan sin alterar el estado.
- [x] Reporte periódico con periodo **definido y justificado**.
- [x] Movimiento progresivo con **velocidad máxima configurable**.
- [x] Ciclo principal **sin `delay()`**.
- [x] Política de arbitraje entre mando físico y digital.
- [x] Parser serial no bloqueante, con validación de prefijo, rango y línea completa.

> Pendiente: experimento A (error angular con transportador) y verificación de la estabilidad
> del contacto del potenciómetro en el montaje final.

### Representación digital (Godot)

- [ ] Escena que simula la situación 7 y se reconoce sin explicación.
- [ ] La variable se actualiza automáticamente con cada reporte `S:`.
- [ ] Mando digital que se envía automáticamente como comando `A:`.
- [ ] Lectura del puerto con GdSerial **sin bloquear el hilo principal**.
- [ ] Las actualizaciones recibidas **no se reenvían** como comandos.

### Política de arbitraje

- [ ] Regla explícita de qué mando prevalece y en qué condiciones.
- [ ] Tratamiento justificado del ruido del potenciómetro (umbral, filtrado o histéresis).
- [ ] Comparación con al menos una alternativa, identificando **en qué casos falla cada una**.

---

## Experimentos

### Experimento A — error angular

Cinco ángulos dentro del rango útil, **tres repeticiones** por ángulo. Se mide la posición del
servo con transportador y se compara con el valor mostrado en la representación digital. Se
reportan **error promedio**, **error máximo** y si el error depende del ángulo.

### Experimento B — coherencia tras conflicto

Diez alternancias entre mando físico y digital. En cada una se registra si el estado final del
servo y el de la representación coinciden dentro de una **tolerancia definida por el grupo**, y
el **tiempo de estabilización**.

> Antes de medir hay que fijar y documentar la tolerancia: sin ella los resultados no son
> interpretables.

---

## Entregables

1. Repositorio con el firmware, el proyecto de Godot y las instrucciones de ejecución.
2. Video editado de máximo 3 minutos, con secciones y con el sistema físico y la representación
   visibles a la vez.
3. Póster en PDF, proporción DIN A1 vertical, con el logotipo de la Universidad.

Los criterios detallados están en [rubrica.md](./rubrica.md) y el enunciado completo en
[enunciado.md](./enunciado.md).

---

## Cómo ejecutar

### Firmware

```bash
# Compilar
pio run

# Compilar y subir a la placa
pio run --target upload --upload-port /dev/ttyUSB0

# Ver los reportes S: a 9600 baudios
pio device monitor --port /dev/ttyUSB0
```

- En Windows el puerto se llama `COM3`, `COM4`, … (`pio device list` los muestra).
- Si `pio` no está en el `PATH` (PlatformIO instalado como extensión de VS Code), el
  ejecutable está en `~/.platformio/penv/bin/pio`.
- El `platformio.ini` ya fija la placa y la velocidad del bootloader; no hace falta pasar
  más opciones.

Mientras el monitor esté abierto, el puerto queda ocupado y Godot no podrá abrirlo.

### Escena de Godot

*Pendiente.* Cuando la escena esté lista, esta sección documentará:

1. Copia de `addons/gdserial/` al proyecto y activación en
   **Project → Project Settings → Plugins**.
2. Selección del puerto en el inspector (`/dev/ttyUSB0` o `/dev/ttyACM0` en Linux, `COM3` en
   Windows).
3. Permisos del puerto en Linux: el usuario debe pertenecer al grupo `dialout`.
4. Verificación de ambos flujos y de la política de arbitraje.

> El addon y el firmware deben usar la **misma velocidad** (9600 baudios en este laboratorio).

---

## Equipo

| Integrante | Rol |
| --- | --- |
| *(por completar)* | |

---

## Referencias principales

- Kritzinger, W. et al. (2018). *Digital Twin in manufacturing: A categorical literature review
  and classification.* IFAC-PapersOnLine, 51(11). <https://doi.org/10.1016/j.ifacol.2018.08.474>
- Arduino. *Servo library — Reference.* <https://docs.arduino.cc/libraries/servo/>
- Arduino. *`millis()` — Language Reference.*
  <https://docs.arduino.cc/language-reference/en/functions/time/millis/>
- Arduino. *`attachInterrupt()` — Language Reference.*
  <https://docs.arduino.cc/language-reference/en/functions/external-interrupts/attachInterrupt/>
- Sujith Christopher. *GdSerial — Serial Communication Library for Godot 4.*
  <https://github.com/SujithChristopher/gdserial>
- Godot Engine. *Thread-safe APIs.*
  <https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html>

La bibliografía completa, con anotaciones sobre qué aporta cada fuente, está al final de cada
guía en [lectura_previa/](./lectura_previa/).

