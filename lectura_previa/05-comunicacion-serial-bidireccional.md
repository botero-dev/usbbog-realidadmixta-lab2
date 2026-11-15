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
4. Leer el puerto desde Godot **sin congelar el hilo principal** con GdSerial.
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
| Godot → Arduino | `A:<angulo>` | `A:135` | Entero, 0 ≤ ángulo ≤ 180, línea completa |
| Arduino → Godot | `S:<angulo>,<fuente>` | `S:135,DIG` | Entero 0–180 y fuente `POT` o `DIG` |

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

## 5.6. GdSerial: el puente entre Godot y el puerto

**GdSerial** es un addon para Godot 4 escrito en **Rust** sobre `gdext` (los *bindings* Rust
de GDExtension) que expone una API parecida a PySerial. Se carga como **extensión nativa**, así
que no hay que compilar el motor ni instalar Python: el addon trae bibliotecas ya compiladas
por plataforma y arquitectura.

| Dato | Valor |
| --- | --- |
| Autor y licencia | Sujith Christopher · MIT |
| Versión usada en el proyecto anterior del curso | 0.3.4 |
| Requisito | Godot **4.4 o superior** |
| Plataformas con binarios | Windows x64/ARM64, Linux x64/ARM64, macOS x64/ARM64 |
| Dependencias internas | `gdext` y la caja `serialport` de Rust |
| Plataformas sin soporte | **WebGL / Web**: un navegador no puede abrir un puerto serial |

### Instalación

1. Copiar la carpeta `addons/gdserial/` al directorio `addons/` del proyecto.
2. Activarla en **Project → Project Settings → Plugins**.
3. Verificar que el archivo `gdserial.gdextension` apunte a una biblioteca de **tu**
   plataforma y arquitectura. Si falta la carpeta `bin/` correspondiente, el plugin no carga y
   `GdSerial` aparece como identificador desconocido.

Una vez activo, las clases `GdSerial` y `GdSerialManager` quedan disponibles en GDScript **sin
`preload` ni `import`**: son tipos del motor, no scripts.

> **Antecedente del grupo.** En el proyecto anterior de la asignatura se usó este mismo addon a
> 115200 baudios, con un protocolo de líneas y el patrón `bytes_available()` + `read_string()`
> dentro de `_process`; la escena no se bloqueó. Eso no exime de justificarlo aquí: aquel
> enlace era unidireccional (del dispositivo a la escena) y este es bidireccional, con un
> requisito explícito de sincronización en ambos sentidos.

### Dos clases, dos filosofías

| Clase | Modelo | Uso típico |
| --- | --- | --- |
| `GdSerial` | Síncrona, un solo puerto, todo desde el hilo principal | Sondeo manual en `_process` |
| `GdSerialManager` | Asíncrona, varios puertos, un **hilo lector** por puerto y señales | Aplicaciones que no deben hacer E/S en el hilo principal |

Las dos sirven para este laboratorio. La diferencia está en **dónde ocurre el bloqueo**, y ese
es justo el punto que hay que entender antes de elegir.

---

## 5.7. `GdSerial`: la API síncrona

### Configuración del puerto

| Método | Para qué | Valor por defecto |
| --- | --- | --- |
| `list_ports() -> Dictionary` | Enumera puertos con `port_name`, `device_name`, `port_type` | — |
| `set_port(nombre: String)` | `"COM3"`, `"/dev/ttyUSB0"`, `"/dev/ttyACM0"` | — |
| `set_baud_rate(rate: int)` | Velocidad | 9600 |
| `set_data_bits(bits: int)` | 6, 7 u 8 | 8 |
| `set_parity(tipo: int)` | 0 ninguno, 1 impar, 2 par | 0 |
| `set_stop_bits(bits: int)` | 1 o 2 | 1 |
| `set_flow_control(tipo: int)` | 0 ninguno, 1 software, 2 hardware | 0 |
| `set_timeout(ms: int)` | Tiempo máximo de **cada** lectura | **1000 ms** |
| `open() -> bool` | Abre con la configuración actual | — |
| `close()` | Cierra y libera | — |
| `is_open() -> bool` | Comprueba conexión de forma activa | — |

> La configuración se aplica **al abrir**. Cambiar `set_baud_rate()` con el puerto abierto no
> tiene efecto hasta cerrar y volver a abrir.

### Operaciones de datos

| Método | Qué hace |
| --- | --- |
| `write(PackedByteArray) -> bool` | Escribe bytes y hace `flush` |
| `write_string(String) -> bool` | Igual, desde texto |
| `writeline(String) -> bool` | Añade `\n` al final y escribe |
| `read(size: int) -> PackedByteArray` | Lee **hasta** `size` bytes, sin esperar a completarlos |
| `read_string(size: int) -> String` | Igual, convertido a UTF-8 |
| `readline() -> String` | Lee byte a byte hasta `\n`, hasta el timeout o hasta que no haya datos |
| `bytes_available() -> int` | Bytes esperando en el búfer del sistema |
| `clear_buffer() -> bool` | Vacía los búferes de entrada y salida |

---

## 5.8. ¿Permite GdSerial lecturas no bloqueantes?

**Sí, pero no por el método que uno esperaría.** La respuesta corta es que `GdSerial` no
ofrece un `read_nonblocking()`; lo que ofrece es un **patrón de sondeo** con
`bytes_available()` y un **timeout configurable** que decide cuánto puede esperar una lectura.
La respuesta larga, que es la que sirve para el informe, está en esta tabla:

| Llamada | ¿Bloquea el hilo? | Hasta cuándo |
| --- | --- | --- |
| `bytes_available()` | **No** | Consulta `bytes_to_read()` y retorna de inmediato |
| `read(n)` / `read_string(n)` | **Sí, si no hay datos** | Hasta que llegue algo **o** venza `set_timeout()` |
| `readline()` | **Sí** | Hasta `\n`, hasta el timeout, o hasta que una lectura devuelva 0 |
| `write()` / `writeline()` | Depende | `write_all` + `flush`; con 6 bytes es despreciable |
| `open()` / `close()` | Depende | Apertura/cierre del dispositivo; decenas de milisegundos |
| `is_open()` | No, pero cuesta | Hace una operación de prueba (`bytes_to_read()`) para detectar desconexión |

### Por qué: qué dice el código fuente

Tres hechos verificados en el código del addon (`src/lib.rs`):

1. `open()` configura el puerto con `.timeout(self.timeout)`, y el valor por defecto del
   atributo es **1000 ms**.
2. `read()` llama directamente a `port.read(&mut buffer)`. Es decir, espera **hasta que haya al
   menos un byte o hasta que venza el timeout**; no espera a completar `size` bytes (eso es lo
   que la referencia de clase llama "non-blocking reads").
3. `readline()` hace un bucle de lecturas de **un byte** hasta encontrar `\n` o hasta que una
   lectura devuelva error o cero. Si no hay nada, la primera lectura consume **todo el
   timeout**.

Conclusión: llamar `read()` o `readline()` sin comprobar antes si hay datos puede congelar el
`_process` hasta **un segundo entero**. Ese es exactamente el fallo que el enunciado prohíbe.

### Las dos formas correctas de no bloquear

**a) Sondeo con `bytes_available()`.** Nunca se lee si no hay bytes, así que la lectura
encuentra datos y retorna enseguida:

```gdscript
func _process(_delta: float) -> void:
	var disponibles := _serial.bytes_available()
	if disponibles > 0:
		_buffer += _serial.read_string(disponibles)
```

Y, como red de seguridad, `set_timeout(0)`: con timeout cero la lectura no espera ni cuando se
la llama por error. La propia librería contempla ese caso (su hilo lector duerme 5 ms para no
girar en vacío ante `WouldBlock` cuando el timeout es 0). Conviene confirmarlo en el montaje
antes de afirmarlo en el informe.

**b) `GdSerialManager`.** El bloqueo existe, pero ocurre en un hilo aparte; el hilo principal
solo recoge resultados.

> **Trampa clásica:** `readline()` parece la forma "elegante" de leer un protocolo por líneas y
> es la que más veces cuelga una escena. Si se usa la API síncrona, el troceado por líneas se
> hace **a mano** con un búfer propio (sección 5.11).

---

## 5.9. `GdSerialManager`: hilos, canal y `poll_events()`

La API avanzada evita el problema de raíz: **el hilo principal no toca el puerto**.

### Cómo funciona por dentro

1. `open(puerto, baudios, timeout, modo)` abre el puerto y **lanza un hilo lector** por puerto.
2. Ese hilo lee en bloques de hasta 1024 bytes y empuja eventos a un **canal** interno
   (`mpsc::channel` en Rust): datos recibidos o desconexión.
3. Después de cada intento duerme **5 ms** para no girar en vacío.
4. `poll_events()` —llamado desde `_process`— vacía el canal y **emite las señales en el hilo
   principal**, que es lo que respeta la regla de Godot de no tocar el árbol de escena desde
   otros hilos.

### API

| Método | Descripción |
| --- | --- |
| `open(nombre, baudios, timeout_ms, modo = 0) -> bool` | Abre y arranca el hilo lector |
| `close(nombre)` | Cierra y **detiene** el hilo; descarta los datos pendientes |
| `is_open(nombre) -> bool` | ¿Está abierto y el hilo activo? |
| `write(nombre, PackedByteArray) -> bool` | Escritura; documentada como segura entre hilos |
| `set_delimiter(nombre, byte) -> bool` | Delimitador para el modo 2 |
| `reconfigure_port(...) -> bool` | Cambia bits, paridad, stop bits, flujo y timeout |
| `poll_events() -> Array` | **Obligatorio** en `_process`; emite las señales y devuelve los eventos |

Señales:

| Señal | Argumentos | Cuándo |
| --- | --- | --- |
| `data_received` | `port: String`, `data: PackedByteArray` | Llegó información |
| `port_disconnected` | `port: String` | El dispositivo se desconectó |

### Modos de entrega de datos

| Modo | Constante | Comportamiento |
| --- | --- | --- |
| 0 | `MODE_RAW` (por defecto) | Emite cada bloque tal como llega; **puede partir una línea** |
| 1 | `MODE_LINE_BUFFERED` | Acumula hasta `\n` y emite la línea |
| 2 | `MODE_CUSTOM_DELIMITER` | Acumula hasta un byte delimitador configurable |

Detalles que afectan el parser:

- En modo línea, el bloque entregado **incluye el `\n`**: hay que limpiarlo con `strip_edges()`
  antes de comparar.
- Al vencer el timeout, el hilo **vacía lo que tenga acumulado aunque no haya `\n`**. Con un
  timeout corto eso produce líneas truncadas que parecen válidas. Hay que validar el contenido,
  no solo el delimitador.
- La latencia percibida es, aproximadamente, `timeout + 5 ms + tiempo de la trama`.
- `poll_events()` debe llamarse **cada frame**; si no, los eventos se acumulan en el canal.

---

## 5.10. Cuál usar en este laboratorio

| Criterio | `GdSerial` + sondeo | `GdSerialManager` |
| --- | --- | --- |
| Costo en el hilo principal | Una consulta y una lectura por frame | Vaciar el canal y emitir señales |
| Riesgo de congelar la escena | Alto si se usa `readline()` | Bajo: la E/S está en otro hilo |
| Complejidad del código | Baja | Media |
| Varios puertos | No | Sí |
| Troceado por líneas | Se implementa a mano | Lo hace la librería (con la advertencia del timeout) |
| Depuración | Directa | Hay que razonar sobre dos hilos |

**Recomendación para la situación 7:** `GdSerial` con sondeo y `set_timeout(0)`. Hay un solo
puerto, el tráfico es de 5 reportes por segundo y el ciclo de trabajo es trivial; el patrón de
`bytes_available()` deja el hilo principal libre y el código es fácil de explicar en el póster.
`GdSerialManager` es la opción defendible si el grupo quiere demostrar que el hilo principal
**no hace ninguna** operación de E/S, o si más adelante se agrega un segundo dispositivo.

En cualquier caso, el informe debe decir **cuál se usó, por qué y cómo se verificó** que el
hilo principal no se bloquea.

---

## 5.11. Código: sondeo con `GdSerial`

```gdscript
extends Node

signal estado_recibido(angulo: int, fuente: String)

@export var puerto: String = "/dev/ttyUSB0"
@export var baudios: int = 9600

var _serial: GdSerial
var _buffer: String = ""
var _abierto: bool = false

func _ready() -> void:
	_serial = GdSerial.new()
	_serial.set_port(puerto)
	_serial.set_baud_rate(baudios)
	_serial.set_data_bits(8)
	_serial.set_parity(0)          # ninguno
	_serial.set_stop_bits(1)
	_serial.set_flow_control(0)    # ninguno
	_serial.set_timeout(0)         # ninguna lectura puede esperar
	_abierto = _serial.open()
	if not _abierto:
		push_error("No se pudo abrir el puerto %s" % puerto)

func _process(_delta: float) -> void:
	if not _abierto:
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
		_buffer = ""               # desincronización o basura: se descarta

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

func enviar_angulo(angulo: int) -> void:
	if not _abierto:
		return
	_serial.writeline("A:%d" % angulo)
```

Lo que hay que señalar del ejemplo:

- No hay ninguna llamada que pueda esperar: `bytes_available()` y `read_string()` se usan
  siempre en pareja.
- El troceado por líneas es explícito y tolera fragmentos.
- `_buffer` está acotado: si llega basura sin `\n`, no crece sin límite.
- La validación replica la del firmware: prefijo, número, rango y fuente.

---

## 5.12. Código: `GdSerialManager` con señales

```gdscript
extends Node

@export var puerto: String = "/dev/ttyUSB0"

var _manager: GdSerialManager

func _ready() -> void:
	_manager = GdSerialManager.new()
	_manager.data_received.connect(_al_recibir)
	_manager.port_disconnected.connect(_al_desconectar)

	var modo := GdSerialManager.MODE_LINE_BUFFERED
	if not _manager.open(puerto, 9600, 1000, modo):
		push_error("No se pudo abrir el puerto %s" % puerto)

func _process(_delta: float) -> void:
	_manager.poll_events()         # imprescindible

func _al_recibir(puerto_origen: String, datos: PackedByteArray) -> void:
	var linea := datos.get_string_from_utf8().strip_edges()
	if not linea.begins_with("S:"):
		return
	# ... validar y aplicar
	print(puerto_origen, " -> ", linea)

func _al_desconectar(puerto_origen: String) -> void:
	push_warning("Se perdió la conexión con %s" % puerto_origen)
```

Con `_manager.open(..., GdSerialManager.MODE_LINE_BUFFERED)` el troceado ocurre en el hilo
lector y `_al_recibir` se ejecuta en el hilo principal, así que **sí** se puede tocar la escena
dentro de la señal.

---

## 5.13. El problema del eco: no reenviar lo que llega

El requisito "las actualizaciones que llegan del dispositivo no se reenvían como comandos"
suena trivial y no lo es. La cadena típica de un fallo:

```
Arduino envía S:120,POT
   → Godot actualiza el control deslizante por código
      → el control emite value_changed
         → Godot envía A:120
            → el Arduino lo aplica y reporta S:120,DIG
               → la fuente cambia sola, la escena "tiembla" y el mando físico queda anulado
```

Soluciones en Godot, de la más simple a la más robusta:

1. **Bandera de supresión**: mientras se aplica un valor remoto, no se envían comandos.
2. **Actualización sin señal**: `Range` expone `set_value_no_signal(valor)` para `HSlider`,
   `VSlider`, `ProgressBar` y `SpinBox`. También sirve `set_block_signals(true)` alrededor de la
   asignación.
3. **Origen del cambio**: el comando se envía solo desde el manejador de la interacción del
   usuario (`value_changed` conectado a una función que envía), nunca desde la función que
   aplica el estado recibido.
4. **Comparación con histéresis**: no enviar si la diferencia respecto al estado vigente es
   menor que un umbral (cuidado: puede enmascarar comandos legítimos).

La opción 3 es la que mejor se explica en el informe, porque separa **entrada del usuario** de
**sincronización de estado**.

---

## 5.14. Cómo probar el enlace sin el montaje completo

| Prueba | Qué demuestra |
| --- | --- |
| Monitor serial del IDE a 9600 | Que el firmware reporta con el formato y el periodo esperados |
| Enviar `A:90` a mano desde el monitor | Que el comando se aplica y que el reporte cambia a `DIG` |
| Enviar `A:999`, `A:x`, línea sin `\n` | Que los inválidos se descartan sin afectar el estado |
| Par virtual con `socat` en Linux | Que Godot se conecta y que la escena no se congela sin hardware |
| Imprimir `Time.get_ticks_usec()` en `_process` | Que no hay picos de frame atribuibles a la lectura |
| Desconectar el USB en caliente | Que `port_disconnected` (o `is_open()`) se detecta sin errores en cascada |

Ejemplo de par virtual en Linux (dos extremos, uno para Godot y otro para un script de prueba):

```bash
socat -d -d pty,raw,echo=0 pty,raw,echo=0
```

`socat` imprime los dos dispositivos creados (por ejemplo `/dev/pts/5` y `/dev/pts/6`). Se abre
uno desde Godot y se escribe en el otro con `printf 'S:90,POT\n' > /dev/pts/6`.

> **Ojo:** el puerto es un recurso exclusivo. Si el monitor serial del IDE lo tiene abierto,
> Godot no podrá abrirlo (y viceversa).

---

## 5.15. Errores frecuentes en Godot

| Error | Efecto |
| --- | --- |
| `readline()` o `read()` sin comprobar `bytes_available()` | Congelamiento de hasta 1 s por frame |
| `set_timeout()` con el valor por defecto y lectura a ciegas | El mismo congelamiento, más difícil de ver |
| Parsear fragmentos sin `\n` | Comandos fantasma y ángulos imposibles |
| `int()` sobre texto no validado | `"abc"` se convierte en 0 y mueve el servo |
| Reenviar `S:` como `A:` | Oscilación, fuente que cambia sola, mando físico anulado |
| No llamar `poll_events()` | Las señales del manager nunca llegan |
| Usar `String +=` con un búfer sin límite | Crecimiento indefinido si el flujo se desincroniza |
| No activar el plugin | `GdSerial` aparece como identificador desconocido |
| Faltan los binarios de tu arquitectura | El plugin carga pero las clases no existen |
| Abrir el puerto desde el editor y desde el juego a la vez | `open()` devuelve `false` |
| Exportar a Web | No existe acceso a serial en el navegador |

---

## 5.16. Preguntas de autoevaluación

1. ¿Cuántos bytes por segundo caben a 9600 baudios con 8N1 y cuánto tarda un reporte de 10
   bytes?
2. ¿Por qué el protocolo usa un delimitador de línea en lugar de un prefijo de longitud?
3. ¿Qué debe hacer el firmware con `A:181`? ¿Y con `A:90` sin salto de línea?
4. ¿Qué llamadas de `GdSerial` pueden bloquear y hasta cuándo?
5. ¿Qué hace exactamente `poll_events()` y por qué debe llamarse en `_process`?
6. ¿Cómo se evita que una actualización recibida se reenvíe como comando?
7. ¿Qué evidencia recogería para demostrar que la lectura del puerto no bloquea el hilo
   principal?

---

## 5.17. Fuentes consultadas

1. **Sujith Christopher.** *GdSerial — Serial Communication Library for Godot 4* (repositorio,
   README y notas de versión). <https://github.com/SujithChristopher/gdserial>
   → Instalación, API de `GdSerial` y `GdSerialManager`, modos de búfer y requisitos de
   plataforma. Es la fuente primaria para todo lo de Godot.

2. **GdSerial — referencia de clase `GdSerial`** (`addons/gdserial/doc/en/GdSerial.xml`).
   <https://github.com/SujithChristopher/gdserial/blob/main/addons/gdserial/doc/en/GdSerial.xml>
   → Comportamiento declarado de `read()`, `readline()`, `set_timeout()` y `bytes_available()`;
   es la documentación que aparece en la ayuda integrada de Godot.

3. **GdSerial — referencia de clase `GdSerialManager`**
   (`addons/gdserial/doc/en/GdSerialManager.xml`).
   <https://github.com/SujithChristopher/gdserial/blob/main/addons/gdserial/doc/en/GdSerialManager.xml>
   → Hilos lectores, modos `MODE_RAW` / `MODE_LINE_BUFFERED` / `MODE_CUSTOM_DELIMITER`, señales
   y contrato de `poll_events()`.

4. **GdSerial — código fuente (`src/lib.rs`).**
   <https://github.com/SujithChristopher/gdserial/blob/main/src/lib.rs>
   → Implementación real del hilo lector, del canal `mpsc`, del `sleep` de 5 ms y de las
   lecturas con timeout. Es la evidencia para afirmar qué bloquea y qué no.

5. **serialport-rs.** *`SerialPort` trait* (documentación de la caja de Rust que usa el addon).
   <https://docs.rs/serialport/latest/serialport/>
   → Semántica de `read()`, `bytes_to_read()` y del timeout del puerto.

6. **Godot Engine.** *Thread-safe APIs.*
   <https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html>
   → Qué se puede llamar desde otros hilos y por qué las señales deben emitirse en el principal.

7. **Godot Engine.** *Idle and Physics Processing.*
   <https://docs.godotengine.org/en/stable/tutorials/scripting/idle_and_physics_processing.html>
   → Dónde encaja `_process`, que es el lugar donde se drena el búfer o se llama
   `poll_events()`.

8. **Godot Engine.** *`Range` — Class Reference.*
   <https://docs.godotengine.org/en/stable/classes/class_range.html>
   → `set_value_no_signal()`, la herramienta para actualizar un control sin disparar el envío
   de comandos.

9. **Arduino.** *Serial — Language Reference.*
   <https://www.arduino.cc/reference/en/language/functions/communication/serial/>
   → Funciones de recepción y búfer del lado Arduino.

10. **Arduino.** *`Serial.readStringUntil()` — Language Reference.*
    <https://docs.arduino.cc/language-reference/en/functions/communication/serial/readStringUntil/>
    → Documenta el tiempo de espera que hace bloqueante esta función y que motiva el parser
    propio de la sección 5.5.

11. **Robin2 (Arduino Forum).** *Serial Input Basics — Updated.*
    <https://forum.arduino.cc/t/serial-input-basics-updated/382007>
    → Referencia sobre recepción no bloqueante y validación de tramas **en el lado Arduino**.

---

**Anterior:** [Interrupciones](./04-interrupciones.md) ·
**Volver al** [README del repositorio](../README.md)
