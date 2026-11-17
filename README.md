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

## Demostracion

Una demostracion del sistema funcionando se encuentra en: <https://youtu.be/QV6TZVus5Dc>

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
└── game/                     Proyecto de Godot (4.7)
    ├── project.godot         Escena principal: scenes/radar.tscn
    ├── scenes/radar.tscn     Escena del laboratorio
    ├── scripts/
    │   ├── serial_link.gd    Enlace serial y parser de los reportes S:
    │   ├── radar_control.gd  Mando manual, rutina y cancelación
    │   └── radar_display.gd  Dibujo del radar y detección de blancos
    └── addons/gdserial/      Addon de comunicación serial (MIT)
└── poster/
    ├── poster.html           Fuente del póster (A1 vertical)
    ├── poster.pdf            PDF generado
    ├── build.sh              Render con Chrome/Chromium headless
    └── assets/               Logotipo institucional (opcional)
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
| Sentido de la salida del servo | **Invertido** (`INVERTIR_SALIDA_SERVO = true`): se escribe 180 − ángulo. El potenciómetro y los reportes `S:` no cambian |
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

- [x] Escena que simula la situación 7 y se reconoce sin explicación.
- [x] La variable se actualiza automáticamente con cada reporte `S:`.
- [x] Mando digital que se envía automáticamente como comando `A:`.
- [x] Lectura del puerto con GdSerial **sin bloquear el hilo principal**.
- [x] Las actualizaciones recibidas **no se reenvían** como comandos.
- [x] Rutina automática que se cancela cuando el potenciómetro toma el mando.

> Pendiente de verificar en el montaje: la cancelación de la rutina por movimiento físico del
> potenciómetro (requiere girarlo a mano durante la rutina).

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

```bash
godot --path game          # o abrir game/project.godot en el editor y F5
```

Al arrancar, la escena intenta conectarse al primer puerto USB/ACM que encuentre y lo muestra
en el campo de texto; si falla, se indica el motivo y se puede escribir el puerto a mano.

| Control | Función |
| --- | --- |
| Puerto + **Conectar** | Abre o cierra el enlace con GdSerial |
| Deslizador 0–180° | Mando digital manual: envía `A:` (máximo ~25 comandos/s) |
| **Iniciar rutina** | Barrido automático entre 10° y 170°, 3° cada 50 ms (60 °/s) |
| **Detener** | Cancela la rutina |
| Radar | **Semicírculo** con el centro en la base: refleja siempre el ángulo reportado y los blancos se mueven dentro del arco; solo se iluminan cuando el haz pasa por su azimut |

Reglas de comportamiento:

- **La escena sigue al servo, no al revés.** El deslizador y el radar se actualizan con cada
  reporte `S:`, venga el mando del potenciómetro o de la escena.
- **Sin reenvíos.** Las actualizaciones recibidas se aplican con `set_value_no_signal()`, así
  que no generan comandos `A:`.
- **La rutina se cancela** cuando (a) llega un reporte `POT`, es decir, el potenciómetro tomó
  el mando; (b) el usuario mueve el deslizador; (c) se pulsa *Detener*; o (d) se cae la
  conexión. En (a) hay una ventana de gracia de 0,5 s al inicio para no confundir un reporte
  `POT` rezagado con un movimiento real.
- **Mapeo de la situación:** los 0–180° del servo se reparten en un **arco de -90° a +90°**
  con el centro en la base del control: 0° del servo queda a la izquierda, 90° arriba y 180°
  a la derecha. Los blancos rebotan en los extremos del arco, así que un blanco fuera del
  sector de barrido simplemente no se detecta.

En Linux el usuario debe pertenecer al grupo `dialout` para abrir el puerto.

> El addon y el firmware deben usar la **misma velocidad** (9600 baudios en este laboratorio).
> La escena anterior del curso (`game/scenes/root.tscn`) sigue en el proyecto, pero ya no es la
> escena principal.

---

## Póster

```bash
poster/build.sh                    # busca Chrome/Chromium automáticamente
CHROME=/ruta/al/chrome poster/build.sh
```

- Formato A1 vertical (594 × 841 mm) definido con `@page size`, en una sola página.
- Tipografía sin adornos y tamaños mínimos según el enunciado.
- Cuatro colores: azul `#003C71`, dorado `#C9A227`, tinta `#14213D` y blanco.
- Cada bloque de texto queda por debajo de las 10 líneas y las figuras y tablas llevan
  título, como pide el enunciado.
- **Logotipo:** `poster/assets/logo_usb.jpg` (2560 × 997 px), dibujado a 44 mm de alto en el
  extremo derecho del encabezado. Si el archivo no existe, el encabezado muestra un recuadro
  con el nombre de la universidad, así que el PDF se puede generar igual.
- **Tipografía:** fuente sin adornos (Liberation Sans, métrica de Arial) y los tamaños mínimos
  del enunciado: título 54 pt, subtítulos 48 pt, autores y filiación 30 pt, texto 28 pt, pies de
  figura 24 pt. La familia y los tamaños están centralizados en las variables de `:root`.
- **Pendiente:** reemplazar los nombres de los integrantes y completar las tablas 2 y 3 con los
  datos de los experimentos A y B.

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

