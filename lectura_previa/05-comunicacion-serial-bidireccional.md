# 5. Comunicación serial bidireccional

**Guía de lectura del pre-laboratorio** · Tema 5 del enunciado
**Tiempo estimado:** 75–90 min · **Fuentes al final del documento**

---

## 5.1. Qué debe quedar claro

Este es el tema que más impacta la rúbrica: de él dependen el *protocolo sin desviaciones*, la
*sincronización bidireccional* y la ausencia de reenvíos. Al terminar debe poder:

1. Explicar cómo viaja un byte por un enlace UART y cuánto tarda.
2. Diseñar un delimitador de mensajes y justificar por qué ese y no otro.
3. Escribir un parser en el Arduino que **no bloquee** y que descarte mensajes inválidos.
4. Leer el puerto desde Unity **sin congelar el hilo principal**.
5. Explicar por qué una actualización que llega del dispositivo no debe reenviarse como comando.

---

## 5.2. El enlace físico: UART a 9600 baudios

El Arduino y el computador hablan por un **UART** (a través de un conversor USB-serial en la
placa). La configuración del laboratorio es **8N1**:

| Elemento | Bits |
| --- | --- |
| Bit de inicio | 1 (siempre 0) |
| Datos | 8 |
| Paridad | Ninguna |
| Bit de parada | 1 (siempre 1) |
| **Total por byte** | **10 bits** |

Cuentas que hay que poder hacer de cabeza:

- 9600 baudios ÷ 10 bits por byte = **960 bytes/s**.
- 1 byte ≈ **1,04 ms**.
- `A:180\n` son 6 bytes → **≈6,25 ms**.
- `S:180,POT\n` son 10 bytes → **≈10,4 ms**.

A 9600 baudios el enlace es **lento**. Eso condiciona el periodo de reporte, el tamaño de los
mensajes y el diseño del parser. El enlace es **full-duplex**: la transmisión y la recepción
son independientes, así que un `S:` no "choca" con un `A:` en el cable. Los conflictos que
aparezcan serán **lógicos** (quién manda), no eléctricos.

---

## 5.3. Delimitar mensajes en un flujo continuo

Un puerto serial entrega **bytes**, no mensajes. No hay noción de "paquete". Si llegan
`S:90,POT\nS:91,POT\n`, el receptor debe decidir dónde termina uno y empieza el otro. Tres
estrategias habituales:

| Estrategia | Cómo funciona | Ventaja | Costo |
| --- | --- | --- | --- |
| **Delimitador** (`\n`) | Se acumulan bytes hasta el delimitador | Simple, legible, fácil de depurar | Un carácter reservado; hay que escapar si aparece en los datos |
| **Prefijo de longitud** | El mensaje empieza con su tamaño | No necesita delimitador; robusto con binario | Menos legible; un byte corrupto desincroniza |
| **Trama binaria con cabecera y CRC** | Cabecera, longitud, carga, verificación | Muy robusto | Complejo; innecesario para texto a 9600 |

El laboratorio usa **texto con delimitador de línea**: es la opción correcta porque el volumen
es bajo, la legibilidad importa para depurar y el formato es el mismo que muestra el monitor
serial.

### La regla de oro

> Un mensaje solo es válido si está **completo** (termina en `\n`), tiene el **prefijo
> esperado**, el **número de campos** correcto y los **valores en rango**. Cualquier otra cosa
> se descarta **sin bloquear** y sin afectar el estado vigente.

---

## 5.4. El protocolo del laboratorio

| Sentido | Formato | Ejemplo | Validación |
| --- | --- | --- | --- |
| Unity → Arduino | `A:<angulo>` | `A:135` | Entero, 0 ≤ ángulo ≤ 180, línea completa |
| Arduino → Unity | `S:<angulo>,<fuente>` | `S:135,DIG` | Entero 0–180 y fuente `POT` o `DIG` |

Casos límite que el firmware debe manejar sin romperse:

| Entrada | Comportamiento esperado |
| --- | --- |
| `A:180` | Se acepta (límite superior incluido) |
| `A:181` | Se descarta; el ángulo vigente no cambia |
| `A:-5` | Se descarta |
| `A:abc` | Se descarta |
| `A:` | Se descarta (falta el valor) |
| `A:90` sin `\n` | **No** se procesa todavía: puede ser una línea incompleta |
| `A:90\nA:100\n` en una sola lectura | Se procesan dos comandos, en orden |
| Basura entre mensajes (`xxA:90\n`) | Se descarta el fragmento y se resincroniza en el siguiente prefijo |
| `S:90,POT` recibido por el Arduino | Se ignora: es un mensaje de salida |

Ese último caso es importante: el Arduino **no debe** interpretar sus propios reportes si por
algún motivo vuelven por el puerto (por ejemplo, en una prueba de eco).

---

## 5.5. Lado Arduino: parser sin bloqueo

El patrón es siempre el mismo: **acumular, delimitar, validar y actuar**, sin esperar.

```cpp
const uint8_t MAX_LINEA = 24;
char linea[MAX_LINEA];
uint8_t n = 0;
bool descartando = false;

void atenderSerial() {
  while (Serial.available() > 0) {
    char c = (char)Serial.read();

    if (c == '\n') {
      if (!descartando && n > 0) {
        linea[n] = '\0';
        procesarLinea(linea);
      }
      n = 0;
      descartando = false;
      continue;
    }

    if (c == '\r') continue;            // tolera CRLF

    if (n < MAX_LINEA - 1) {
      linea[n++] = c;
    } else {
      descartando = true;               // línea demasiado larga: se tira
      n = 0;
    }
  }
}

void procesarLinea(const char *s) {
  if (s[0] != 'A' || s[1] != ':') return;   // prefijo incorrecto: se descarta

  char *fin = nullptr;
  long valor = strtol(s + 2, &fin, 10);

  if (fin == s + 2 || *fin != '\0') return; // no era un número limpio
  if (valor < 0 || valor > 180) return;     // fuera de rango
  aplicarComandoDigital((int)valor);
}
```

Detalles que evalúa la rúbrica:

- **Nunca** se usa `readStringUntil()` ni `parseInt()`: ambos esperan hasta el timeout (1 s por
  defecto) y bloquean el ciclo.
- La línea se procesa **solo al ver `\n`**. Un fragmento no se interpreta.
- El búfer es de tamaño fijo y **acotado**: si la línea excede el máximo, se descarta entera en
  lugar de desbordar memoria.
- `strtol` con verificación de `fin` rechaza `12abc` y `A:abc`.
- El descarte **no** modifica el ángulo vigente ni la fuente.

### El búfer de recepción es finito

En AVR el búfer de recepción de `Serial` es de **64 bytes**, se llena por interrupción y, si
se desborda, los bytes nuevos se **pierden en silencio** (el UART apenas tiene un FIFO de dos
bytes, así que la librería es la que amortigua). Consecuencias prácticas:

- Hay que drenar el puerto con frecuencia (cada vuelta del `loop()`, no cada 200 ms).
- Si llega una ráfaga mayor que el búfer mientras el programa está ocupado, se pierden datos y
  la trama se trunca. El parser debe tolerarlo (por eso valida `\n` y descarta).
- El tamaño del búfer se puede aumentar, pero no es la solución: la solución es no bloquear el
  ciclo.

---

## 5.6. Lado Unity: leer sin congelar el hilo principal

### Las tres reglas

1. **La API de Unity no es segura fuera del hilo principal.** `transform`, `Instantiate`,
   `Debug.Log` (este sí es seguro), componentes, UI: todo debe tocarse en el hilo principal.
2. **`SerialPort.ReadLine()`, `ReadByte()` y `Read()` bloquean** hasta que hay datos o hasta
   que vence `ReadTimeout`. En el `Update()` congelarían la escena.
3. **Los datos deben cruzar de un hilo a otro por una estructura segura**: una cola
   concurrente, y se drenan unas pocas por frame.

### Patrón recomendado

```csharp
using System;
using System.Collections.Concurrent;
using System.IO.Ports;
using System.Threading;
using UnityEngine;

public class EnlaceSerial : MonoBehaviour
{
    [SerializeField] private string puerto = "/dev/ttyUSB0";   // Windows: "COM3"
    [SerializeField] private int baudios = 9600;

    private SerialPort _sp;
    private Thread _hilo;
    private volatile bool _activo;
    private readonly ConcurrentQueue<string> _lineas = new ConcurrentQueue<string>();

    private void Start()
    {
        _sp = new SerialPort(puerto, baudios)
        {
            NewLine = "\n",
            ReadTimeout = 100,
            WriteTimeout = 100,
            DtrEnable = false,
            RtsEnable = false
        };
        _sp.Open();

        _activo = true;
        _hilo = new Thread(Leer) { IsBackground = true, Name = "SerialReader" };
        _hilo.Start();
    }

    private void Leer()
    {
        var buffer = new System.Text.StringBuilder(64);

        while (_activo)
        {
            try
            {
                int b = _sp.ReadByte();          // bloquea con timeout de 100 ms
                if (b < 0) continue;
                if (b == '\n')
                {
                    _lineas.Enqueue(buffer.ToString());
                    buffer.Clear();
                }
                else if (b != '\r' && buffer.Length < 64)
                {
                    buffer.Append((char)b);
                }
            }
            catch (TimeoutException) { /* normal: no llegó nada */ }
            catch (Exception e)
            {
                Debug.LogWarning($"Serial: {e.Message}");
                break;
            }
        }
    }

    private void Update()
    {
        // Se drenan como máximo N mensajes por frame para no crear picos
        for (int i = 0; i < 8 && _lineas.TryDequeue(out string linea); i++)
            ProcesarLinea(linea);
    }

    public void EnviarAngulo(int angulo)
    {
        if (_sp == null || !_sp.IsOpen) return;
        _sp.Write($"A:{angulo}\n");
    }

    private void OnDestroy()
    {
        _activo = false;
        _hilo?.Join(200);
        if (_sp != null && _sp.IsOpen) _sp.Close();
        _sp?.Dispose();
    }
}
```

Por qué este patrón cumple los requisitos:

- El hilo lector **puede bloquearse tranquilo**: es un hilo aparte.
- El `Update()` nunca espera: solo consulta la cola.
- El límite de 8 mensajes por frame evita que una ráfaga produzca un pico de trabajo.
- `IsBackground = true` garantiza que el hilo no impida cerrar la aplicación.
- Se cierra el puerto en `OnDestroy`: un puerto abierto impide reabrir la escena sin reiniciar
  el editor.

### Alternativa: evento `DataReceived`

`SerialPort.DataReceived` se dispara en un hilo del *thread pool*, no en el hilo principal.
Sirve, pero con dos cuidados: el manejador debe solo encolar (nunca tocar Unity) y hay que
tener presente que el evento puede dispararse varias veces por trama. Para este laboratorio,
el hilo dedicado es más fácil de razonar y de depurar.

### Detalles del entorno que cuestan horas

| Situación | Qué hacer |
| --- | --- |
| El Arduino se reinicia al conectar | Al abrir el puerto, el flanco de DTR reinicia la placa; esperar ~2 s antes de enviar |
| `System.IO.Ports` no compila | Cambiar *Api Compatibility Level* a **.NET Framework** en Player Settings |
| No aparece el puerto en Linux | Agregar el usuario al grupo `dialout`; el puerto suele ser `/dev/ttyUSB0` o `/dev/ttyACM0` |
| `COM10` no se abre en Windows | Usar `\\.\COM10` como nombre |
| WebGL | No hay acceso a puertos seriales; la escena debe probarse en el editor o en un *standalone* |
| Dos programas abren el puerto | El segundo falla: el recurso es exclusivo (cerrar el monitor serial del IDE) |

---

## 5.7. El problema del eco: no reenviar lo que llega

El requisito "las actualizaciones que llegan del dispositivo no se reenvían como comandos"
suena trivial y no lo es. La cadena típica de un fallo es:

```
Arduino envía S:120,POT
   → Unity actualiza el slider (por código)
      → el slider dispara onValueChanged
         → Unity envía A:120
            → el Arduino lo aplica y reporta S:120,DIG
               → la fuente cambia sola, la escena "tiembla" y el mando físico queda anulado
```

Soluciones, de la más simple a la más robusta:

1. **Bandera de supresión**: mientras se aplica un valor remoto, no se envían comandos.
2. **Actualización sin notificación**: en uGUI, `Slider.SetValueWithoutNotify()`; en UI Toolkit,
   asignar el valor sin registrar el callback.
3. **Origen del cambio**: el comando se envía solo desde el manejador de eventos de usuario,
   nunca desde el método que aplica el estado recibido.
4. **Comparación con histéresis**: no enviar si el cambio solicitado difiere del estado vigente
   en menos que un umbral (cuidado: esto puede enmascarar comandos legítimos).

La opción 3 es la que mejor se explica en el informe, porque separa **entrada del usuario** de
**sincronización de estado**.

---

## 5.8. Cómo probar el enlace sin el montaje completo

| Prueba | Qué demuestra |
| --- | --- |
| Monitor serial del IDE a 9600 | Que el firmware reporta con el formato y el periodo esperados |
| Enviar `A:90` a mano desde el monitor | Que el comando se aplica y que el reporte cambia a `DIG` |
| Enviar `A:999`, `A:x`, línea sin `\n` | Que los inválidos se descartan sin afectar el estado |
| Puente TX–RX (loopback) | Que el parser acepta exactamente lo que él mismo emite |
| Par virtual (`socat` en Linux) | Que Unity se conecta sin hardware y que el hilo no bloquea |
| Marca de tiempo al enviar y al recibir | Latencia real del lazo, para el experimento B |

---

## 5.9. Errores frecuentes

| Error | Efecto |
| --- | --- |
| `readStringUntil` / `parseInt` en el firmware | Bloqueos de hasta 1 s; se pierden comandos |
| Interpretar fragmentos sin `\n` | Comandos fantasma y ángulos imposibles |
| Parsear con `toInt()` sin validar | `A:abc` se convierte en 0 y mueve el servo |
| `ReadLine()` en `Update()` | La escena se congela cuando no hay datos |
| Tocar `transform` desde el hilo lector | Excepciones intermitentes difíciles de reproducir |
| Reenviar `S:` como `A:` | Oscilación, fuente que cambia sola, mando físico anulado |
| Un objeto nuevo por mensaje en cada frame | Presión de *garbage collector* y tirones |
| No cerrar el puerto | El editor no puede volver a abrirlo sin reiniciarse |

---

## 5.10. Preguntas de autoevaluación

1. ¿Cuántos bytes por segundo caben a 9600 baudios con 8N1 y cuánto tarda un reporte de 10
   bytes?
2. ¿Por qué el protocolo usa un delimitador de línea en lugar de un prefijo de longitud?
3. ¿Qué debe hacer el firmware con `A:181`? ¿Y con `A:90` sin salto de línea?
4. ¿Por qué `ReadLine()` en `Update()` congela la escena y un hilo aparte no?
5. ¿Cómo se evita que una actualización recibida se reenvíe como comando?
6. ¿Qué evidencia recogería para demostrar que la lectura del puerto no bloquea el hilo
   principal?

---

## 5.11. Fuentes consultadas

1. **Arduino.** *Serial — Language Reference.*
   <https://www.arduino.cc/reference/en/language/functions/communication/serial/>
   → Funciones disponibles, búfer de recepción y advertencias de uso.

2. **Robin2 (Arduino Forum).** *Serial Input Basics — Updated.*
   <https://forum.arduino.cc/t/serial-input-basics-updated/382007>
   → Referencia clásica sobre recepción no bloqueante, delimitadores y validación de tramas;
   incluye ejemplos de parser incremental.

3. **Arduino.** *`Serial.readStringUntil()` — Language Reference.*
   <https://docs.arduino.cc/language-reference/en/functions/communication/serial/readStringUntil/>
   → Documenta el comportamiento y el tiempo de espera que la hacen bloqueante.

4. **Arduino.** *`Serial.available()` y `Serial.read()` — Language Reference.*
   <https://docs.arduino.cc/language-reference/en/functions/communication/serial/available/>
   y <https://docs.arduino.cc/language-reference/en/functions/communication/serial/read/>
   → Base del patrón de acumulación byte a byte.

5. **Microsoft Learn.** *`SerialPort` Class.*
   <https://learn.microsoft.com/en-us/dotnet/api/system.io.ports.serialport>
   → Propiedades (`ReadTimeout`, `NewLine`, `DtrEnable`) y funcionamiento general.

6. **Microsoft Learn.** *`SerialPort.ReadLine()` Method.*
   <https://learn.microsoft.com/en-us/dotnet/api/system.io.ports.serialport.readline>
   → Comportamiento bloqueante y excepción por timeout.

7. **Microsoft Learn.** *`ConcurrentQueue<T>` Class.*
   <https://learn.microsoft.com/en-us/dotnet/api/system.collections.concurrent.concurrentqueue-1>
   → Cola segura entre hilos; base del paso de mensajes al hilo principal.

8. **Microsoft Learn.** *Threads and threading.*
   <https://learn.microsoft.com/en-us/dotnet/standard/threading/threads-and-threading>
   → Hilos en segundo plano, sincronización y buenas prácticas.

9. **Unity.** *Order of execution for event functions.*
   <https://docs.unity3d.com/6000.0/Documentation/Manual/execution-order.html>
   → Dónde encaja el drenaje de la cola dentro del frame.

10. **Unity.** *`Application.logMessageReceivedThreaded`.*
    <https://docs.unity3d.com/ScriptReference/Application-logMessageReceivedThreaded.html>
    → Confirma qué parte de la API de Unity tolera llamadas desde otros hilos.

---

**Anterior:** [Interrupciones](./04-interrupciones.md) ·
**Volver al** [README del repositorio](../README.md)
