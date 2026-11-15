# Laboratorio de clase — Gemelo digital con servomotor

**Asignatura:** Laboratorio de clase (Realidad Mixta)
**Facultad de Ingeniería — Universidad de San Buenaventura, Bogotá**
**Enunciado:** Ing. Sergio Alberto Reyes Gómez
**Situación asignada: N.° 7 — Radar de vigilancia**

---

## Descripción

El laboratorio consiste en construir un **gemelo digital** de un sistema físico sencillo: un
servomotor de posición controlado localmente por un potenciómetro y conectado por puerto
serial a una escena de Unity. El sistema debe funcionar en los **dos sentidos**:

- el **mando físico** (potenciómetro) mueve el servo y la escena se actualiza sola;
- el **mando digital** (control en Unity) mueve el servo y el firmware reporta el nuevo estado.

Como ambos mandos pueden actuar a la vez, cada grupo debe diseñar una **política de
arbitraje** que defina cuál prevalece y cómo se trata el ruido del potenciómetro. Después se
mide experimentalmente el **error angular** y la **coherencia de estado** entre los dos lados.

El entregable no es solo un montaje que funciona: es un sistema cuya clasificación como
gemelo digital se sostiene con un marco teórico, una política justificada y datos propios.

---

## Situación 7: radar de vigilancia

| Aspecto | Definición |
| --- | --- |
| Variable controlada por el ángulo | Orientación de la antena del radar |
| Comportamiento a simular | Pantalla de radar con objetos en movimiento que **solo se detectan** cuando la antena apunta hacia ellos |
| Mando físico | Potenciómetro |
| Mando digital | Control en la escena de Unity |
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
├── firmware/                 (pendiente) Código del Arduino
└── unity/                    (pendiente) Proyecto de Unity
```

> **Estado actual:** el repositorio contiene el enunciado, la rúbrica y las guías de lectura.
> Las carpetas `firmware/` y `unity/` se agregan a medida que avanza el desarrollo.

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
| 5 | Comunicación serial bidireccional | [05-comunicacion-serial-bidireccional.md](./lectura_previa/05-comunicacion-serial-bidireccional.md) | Delimitación de mensajes, parser sin bloqueo y lectura no bloqueante desde Unity |

**Cómo usar las guías:** leer una, responder las preguntas de autoevaluación sin mirar el
texto y recién después revisar las fuentes originales. El marco teórico del póster debe salir
de esas fuentes, no de las guías: las guías son un mapa, no la cita.

---

## Arquitectura del sistema

```
┌─────────────┐      A:<angulo>      ┌─────────────┐ S:<angulo>,<fuente>  ┌─────────────┐
│    Unity    │ ──────────────────►  │   Arduino   │ ──────────────────►  │    Unity    │
│    (mando   │                      │    + SG90   │                      │   (escena)  │
│   digital)  │                      │    + pot.   │                      │             │
└─────────────┘                      └─────────────┘                      └─────────────┘
                                            ▲
                                            │ mando físico
                                       potenciómetro
```

### Protocolo de comunicación

Texto plano, **9600 baudios**, terminado en salto de línea (`\n`):

| Sentido | Formato | Función |
| --- | --- | --- |
| Unity → Arduino | `A:<angulo>` | Comando digital; entero entre 0 y 180 |
| Arduino → Unity | `S:<angulo>,<fuente>` | Reporte de estado; `<fuente>` es `POT` (mando físico) o `DIG` (mando digital) |

Reglas que el firmware debe cumplir: los valores fuera de rango y los mensajes mal formados se
**descartan sin afectar el funcionamiento**, y los reportes reflejan los **ángulos intermedios**
del movimiento progresivo, no solo el objetivo.

---

## Requisitos por componente

### Firmware (Arduino)

- [ ] El potenciómetro controla el ángulo del servomotor.
- [ ] Los comandos `A:` se aplican; los inválidos se descartan sin alterar el estado.
- [ ] Reporte periódico con periodo **definido y justificado**.
- [ ] Movimiento progresivo con **velocidad máxima configurable**.
- [ ] Ciclo principal **sin `delay()`**.
- [ ] Política de arbitraje entre mando físico y digital.
- [ ] Parser serial no bloqueante, con validación de prefijo, rango y línea completa.

### Representación digital (Unity)

- [ ] Escena que simula la situación 7 y se reconoce sin explicación.
- [ ] La variable se actualiza automáticamente con cada reporte `S:`.
- [ ] Mando digital que se envía automáticamente como comando `A:`.
- [ ] Lectura del puerto **sin bloquear el hilo principal**.
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

1. Repositorio con el firmware, el proyecto de Unity y las instrucciones de ejecución.
2. Video editado de máximo 3 minutos, con secciones y con el sistema físico y la representación
   visibles a la vez.
3. Póster en PDF, proporción DIN A1 vertical, con el logotipo de la Universidad.

Los criterios detallados están en [rubrica.md](./rubrica.md) y el enunciado completo en
[enunciado.md](./enunciado.md).

---

## Cómo ejecutar

*Pendiente.* Cuando estén disponibles el firmware y la escena, esta sección documentará:

1. Carga del sketch en el Arduino y verificación del puerto.
2. Apertura del proyecto de Unity y de la escena principal.
3. Selección del puerto serial (nombre y permisos según el sistema operativo).
4. Verificación de ambos flujos y de la política de arbitraje.

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
- Microsoft Learn. *`SerialPort` Class.*
  <https://learn.microsoft.com/en-us/dotnet/api/system.io.ports.serialport>

La bibliografía completa, con anotaciones sobre qué aporta cada fuente, está al final de cada
guía en [lectura_previa/](./lectura_previa/).

