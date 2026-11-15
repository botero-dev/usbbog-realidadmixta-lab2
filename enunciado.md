# Laboratorio: Gemelo Digital con Servomotor

**Ing. Sergio Alberto Reyes Gómez**\

Facultad de Ingeniería. Universidad San Buenaventura. Bogotá, Colombia.

## 1. Pregunta orientadora

¿Qué condiciones debe cumplir la relación entre un sistema físico y su representación digital para que esta pueda considerarse un gemelo digital, y cómo se verifica experimentalmente que ambos mantienen un estado coherente cuando pueden ser controlados desde cualquiera de los dos lados?

## 2. Objetivos

1. Implementar un sistema físico basado en un servomotor, con mando local por potenciómetro y comunicación serial bidireccional con Unity, mediante programación no bloqueante.
2. Construir una representación digital que simule el comportamiento de la situación asignada y que se sincronice automáticamente con el sistema físico en ambos sentidos.
3. Diseñar, implementar y justificar una política de arbitraje entre el mando físico y el mando digital.
4. Medir experimentalmente el error angular y la coherencia de estado entre el sistema físico y su representación digital.

## 3. Pre-laboratorio

Antes de iniciar el desarrollo se debe investigar y documentar, con un mínimo de tres fuentes técnicas o académicas, los siguientes temas:

1. **Gemelos digitales.** Definición de gemelo digital y distinción entre modelo digital, sombra digital y gemelo digital según el tipo de intercambio de datos entre el objeto físico y su representación.
2. **Servomotores.** Funcionamiento interno de un servomotor de posición, señal de control por ancho de pulso, diferencias con el servomotor de rotación continua y uso de la librería `Servo.h`, incluidas sus restricciones sobre los temporizadores y las salidas PWM del Arduino.
3. **Programación no bloqueante.** Uso de `millis()` para ejecutar tareas periódicas sin `delay()`, y diferencias entre ambos enfoques en un sistema que debe leer entradas mientras actúa.
4. **Interrupciones.** Qué es una interrupción en un microcontrolador, cómo se configura con `attachInterrupt()`, qué restricciones aplican al código que se ejecuta dentro de ella y en qué casos conviene usarla en lugar de la consulta periódica. Su uso en la implementación es opcional y depende del diseño de cada grupo.
5. **Comunicación serial bidireccional.** Delimitación de mensajes en un flujo serial y estrategias para leer el puerto desde Unity sin bloquear el hilo principal.

## 4. Situaciones asignadas

Cada grupo implementa una situación distinta. El número de la situación corresponde al número del grupo seleccionado en Nexus. En todas, el ángulo del servomotor controla una variable de la situación; la representación digital no se limita a rotar un objeto, sino que debe simular el comportamiento de la situación real descrito en la tabla. Cada grupo define el rango angular útil y su relación con la variable representada.

| N.° | Situación | Variable controlada por el ángulo | Comportamiento mínimo a simular |
| --- | --- | --- | --- |
| 1 | Barrera de parqueadero | Apertura de la pluma | Vehículos que llegan a la entrada, esperan mientras la barrera está cerrada y solo pasan cuando la apertura lo permite. Si la pluma baja con un vehículo debajo, la escena lo evidencia. |
| 2 | Velocímetro de un vehículo | Posición de la aguja (el potenciómetro actúa como acelerador) | Vehículo cuya velocidad corresponde a la indicación de la aguja; el entorno se desplaza de forma coherente con esa velocidad y la escala del indicador está graduada. |
| 3 | Dirección de un vehículo | Ángulo de giro de las ruedas delanteras | Vehículo que avanza a velocidad constante por un circuito con límites; su trayectoria responde al ángulo de giro. |
| 4 | Compuerta de represa | Apertura de la compuerta | Embalse con caudal de entrada constante y caudal de salida dependiente de la apertura; el nivel del agua sube o baja en consecuencia y el flujo de salida es visible. |
| 5 | Grúa torre | Rotación de la pluma | Carga suspendida que oscila por inercia al girar la pluma; zonas de carga y descarga identificables. |
| 6 | Seguidor solar | Inclinación del panel | Sol que recorre el cielo; la potencia generada depende del ángulo de incidencia de la luz sobre el panel y se muestra en la escena. |
| 7 | Radar de vigilancia | Orientación de la antena | Pantalla de radar con objetos en movimiento que solo se detectan cuando la antena apunta hacia ellos. |
| 8 | Cámara de vigilancia giratoria | Orientación horizontal de la cámara | Vista de la cámara mostrada en pantalla; personas en movimiento que entran y salen del campo de visión. |
| 9 | Desviador en banda transportadora | Posición del desviador | Paquetes de distintos tipos que llegan por la banda y caen en un contenedor u otro según la posición del desviador. |
| 10 | Ventana de invernadero | Apertura de la ventana | Temperatura interior que aumenta por radiación solar y disminuye según la apertura; indicador de temperatura visible en la escena. |

## 5. Parte 1. Sistema físico

### 5.1. Montaje

El sistema físico está compuesto por un Arduino, un servomotor de posición (por ejemplo, SG90) y un potenciómetro. El montaje no requiere maqueta: basta con que el eje del servomotor tenga un indicador visible de su posición angular. Si el servomotor produce reinicios del Arduino o movimientos erráticos, debe alimentarse con una fuente externa con tierra común.

### 5.2. Protocolo de comunicación

Todos los grupos usan el mismo formato de mensajes, en texto, a 9600 baudios y terminados en salto de línea (`\n`):

| Sentido | Formato | Función |
| --- | --- | --- |
| Unity → Arduino | `A:<angulo>` | Comando digital. El ángulo es un entero entre 0 y 180. |
| Arduino → Unity | `S:<angulo>,<fuente>` | Reporte de estado. `<fuente>` indica qué mando fijó el ángulo objetivo vigente: `POT` si proviene del potenciómetro (mando físico) y `DIG` si proviene de un comando `A:` enviado desde Unity (mando digital). |

### 5.3. Requisitos del firmware

- El potenciómetro controla el ángulo del servomotor.
- Los comandos `A:` recibidos se aplican al servomotor. Los valores fuera de rango y los mensajes mal formados se descartan sin afectar el funcionamiento.
- El estado se reporta periódicamente, con un periodo definido y justificado por el grupo.
- El servomotor se desplaza hacia el ángulo objetivo de forma progresiva, con una velocidad máxima de giro configurable; el reporte refleja los ángulos intermedios.
- El ciclo principal no usa `delay()`.
- Se implementa una política de arbitraje entre el mando físico y el digital (ver parte 3).

## 6. Parte 2. Representación digital

En Unity se construye la escena de la situación asignada. Los requisitos son:

- La escena simula el comportamiento descrito para la situación, con un nivel de detalle que permita reconocerla como la situación real.
- La variable controlada se actualiza automáticamente con cada reporte `S:` del Arduino.
- La escena ofrece un mando digital (por ejemplo, un control deslizante o la interacción directa con el objeto) cuyo cambio se envía automáticamente como comando `A:`.
- La lectura del puerto serial no bloquea el hilo principal.
- Las actualizaciones que llegan del dispositivo no se reenvían como comandos; solo los cambios hechos por el usuario en la escena generan comandos.

## 7. Parte 3. Dualidad de mando

Cuando se envía un comando digital, el servomotor se mueve, pero el potenciómetro permanece en su posición. Si el firmware aplica en cada ciclo la lectura del potenciómetro, el comando digital se pierde de inmediato. Cada grupo debe proponer una política que defina qué mando prevalece y en qué condiciones, implementarla y justificarla frente a al menos una alternativa. La política debe considerar que la lectura analógica del potenciómetro presenta variaciones aunque no se manipule.

## 8. Experimentos

### 8.1. Experimento A: error angular

Se seleccionan cinco ángulos dentro del rango útil definido por el grupo. Para cada uno se mide con un transportador la posición del servomotor y se compara con el valor que muestra la representación digital. Se realizan tres repeticiones por ángulo y se reportan el error promedio, el error máximo y si el error depende del ángulo.

### 8.2. Experimento B: coherencia tras conflicto

Se alterna diez veces entre el mando físico y el digital. En cada alternancia se registra si el estado final del servomotor y el de la representación coinciden dentro de una tolerancia definida por el grupo, y el tiempo que tarda el sistema en estabilizarse.

## 9. Preguntas de análisis

1. El ángulo que reporta el Arduino, ¿es el ángulo medido del servomotor o el ángulo ordenado? ¿En qué situación la representación mostraría un estado falso y qué se necesitaría para medir el ángulo real? ¿Afecta esto la clasificación del sistema como gemelo digital?
2. Compare la política de arbitraje implementada con al menos una alternativa. ¿En qué casos falla cada una? Use los resultados del experimento B.
3. Si se eliminara uno de los dos flujos de datos, ¿cómo se clasificaría el sistema? ¿Qué consecuencia tendría esa limitación en la situación real asignada?

## 10. Entregables

1. Repositorio en GitHub con el código del firmware y el proyecto Unity, incluyendo las instrucciones necesarias para ejecutarlo.
2. Video editado, de máximo 3 minutos. No se acepta una grabación continua sin edición: el video debe estar organizado en secciones, con cortes, títulos o narración, y mostrar en un mismo plano o en pantalla dividida el sistema físico y la representación digital. Debe incluir, como mínimo:
   - Presentación de la situación asignada y de la escena construida.
   - Funcionamiento de ambos flujos: del mando físico hacia la escena y del mando digital hacia el servomotor.
   - Demostración de la política de arbitraje ante un conflicto de mando.
   - Resumen de los resultados experimentales.
3. Póster en formato PDF, con las siguientes características:
   - **Estructura:** título; autores e institución; introducción con el objetivo del trabajo; marco teórico, correspondiente al pre-laboratorio; metodología, con un diagrama del sistema y el protocolo de comunicación; resultados de los experimentos A y B en tablas o gráficas; análisis y conclusiones; referencias.
   - **Tamaño:** proporción DIN A1 vertical (594 mm × 841 mm).
   - **Tipografía:** fuentes sin adornos (por ejemplo, Arial, Helvética, Tahoma o Verdana) y no más de tres tipos de letra. Tamaños mínimos: título en negrita, 54 pt; subtítulos, 48 pt; autores y filiación, 30 pt; texto, 28 pt; pies de figura, 24 pt.
   - **Organización:** contenido distribuido en bloques y columnas, con lectura de izquierda a derecha y de arriba abajo; cada bloque de texto con un máximo de 10 líneas; márgenes entre secciones.
   - **Color:** no más de cuatro colores, fondo claro y texto oscuro con buen contraste.
   - **Figuras y tablas:** cada una con título. Se recomienda usar cursiva en lugar de subrayado para resaltar.
   - Logotipo de la Universidad de San Buenaventura en la parte superior.
