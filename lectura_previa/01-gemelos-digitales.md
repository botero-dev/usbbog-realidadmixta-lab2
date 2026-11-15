# 1. Gemelos digitales: modelo, sombra y gemelo

**Guía de lectura del pre-laboratorio** · Tema 1 del enunciado
**Tiempo estimado:** 60–75 min · **Fuentes al final del documento**

---

## 1.1. Por qué este tema decide parte de la nota

La rúbrica es explícita: en el criterio *Fundamentación y análisis* se considera imprecisión
conceptual, por ejemplo, **confundir sombra digital y gemelo digital**. No basta con decir
"es un gemelo digital porque hay un modelo 3D que se mueve": hay que justificar la
clasificación con el **tipo de intercambio de datos** entre el objeto físico y su
representación.

Al terminar esta lectura debe poder responder, en dos o tres frases y sin mirar apuntes:

> ¿Qué diferencia un modelo digital de una sombra digital y de un gemelo digital, y en cuál
> de las tres categorías cae el sistema de este laboratorio?

---

## 1.2. Definición de gemelo digital

El término se atribuye a Michael Grieves, que lo introduce hacia 2002–2003 en el contexto de
la gestión del ciclo de vida del producto (*PLM*) con el nombre de *Mirrored Spaces Model*.
La idea central es sencilla: **una réplica virtual de un activo físico, alimentada con datos
del activo, que permite observarlo, simularlo y eventualmente predecir su comportamiento**.

La formalización que suele citarse como referencia es la de la NASA: Glaessgen y Stargel
(2012) definen el gemelo digital como una **simulación multiphísica, multiescala y
probabilística de un vehículo o sistema** que usa los mejores modelos físicos disponibles,
actualizaciones de sensores y el historial de la flota para reflejar el estado del gemelo
físico. Dos ideas de esa definición son las que importan aquí:

1. La representación se **actualiza con datos del objeto físico** (no es un modelo estático).
2. El objetivo es que la réplica sea **fiel y útil para tomar decisiones**, no solo decorativa.

Tao et al. (2019) resumen la literatura industrial y proponen describir un gemelo digital con
**cinco dimensiones**: entidad física, entidad virtual, datos, servicios y conexión. Es un
marco cómodo para ordenar el diseño del laboratorio:

| Dimensión | En este laboratorio |
| --- | --- |
| Entidad física | Arduino + servomotor SG90 + potenciómetro |
| Entidad virtual | Escena de Unity (radar de vigilancia) |
| Datos | Mensajes `A:` y `S:` por el puerto serial |
| Servicios | Simulación del barrido, detección de blancos, registro de eventos |
| Conexión | Enlace serial USB a 9600 baudios, en ambos sentidos |

> **Cuidado con la palabra "modelo".** En la literatura hay dos usos que se cruzan: un
> *modelo digital* puede ser cualquier representación computacional (incluido un CAD), y al
> mismo tiempo "modelo digital" es una **categoría específica** en la clasificación de flujos
> de datos. En este documento se usa siempre en el segundo sentido, salvo que se indique.

---

## 1.3. La clasificación por flujos de datos (Kritzinger et al., 2018)

Kritzinger, Karner, Traar, Henjes y Sihn publicaron en *IFAC-PapersOnLine* una revisión
categórica de la literatura de manufactura en la que clasifican los trabajos según el
**grado de integración de datos** entre el objeto físico y el digital. Distinguen tres
categorías, y el criterio es únicamente **si el flujo es manual o automático en cada sentido**:

| Categoría | Físico → digital | Digital → físico | Consecuencia |
| --- | --- | --- | --- |
| **Modelo digital** | Manual | Manual | Cambiar el objeto físico no cambia la representación y viceversa. La sincronización, si ocurre, la hace una persona. |
| **Sombra digital** (*digital shadow*) | **Automático** | Manual | La representación refleja el estado físico, pero el físico no obedece a la representación. Es un tablero de instrumentos, no un lazo de control. |
| **Gemelo digital** (*digital twin*) | **Automático** | **Automático** | Ambos lados se afectan sin intervención humana. Es la única categoría que cierra el lazo en los dos sentidos. |

Tres precisiones que suelen perderse y que conviene tener presentes:

- **El criterio no es la existencia de un modelo 3D.** Un modelo tridimensional muy detallado
  alimentado a mano sigue siendo un modelo digital. Un gemelo puede ser una tabla de estados.
- **La clasificación no exige tiempo real estricto**, pero sí actualización automática y
  periódica. La discusión sobre latencia y periodo de reporte va en la sección 1.5.
- **El uso del término en la industria no es uniforme.** Varios proveedores llaman "sombra
  digital" a un conjunto de datos derivados (por ejemplo, datos agregados de un activo) y
  "gemelo digital" a cualquier réplica virtual. En el laboratorio se usa la definición de
  Kritzinger, que es la que permite decidir con un criterio verificable. Si en el póster se
  menciona otra convención, hay que decir cuál y por qué se adopta.

---

## 1.4. Cómo se reconoce un gemelo digital en la práctica

Más allá de la etiqueta, un sistema se comporta como gemelo digital cuando cumple estas
condiciones, que son las que el laboratorio pide evidenciar:

1. **Correspondencia uno a uno.** Hay un objeto físico concreto y una representación de *ese*
   objeto, no de una clase de objetos.
2. **Sincronización automática y continua.** Nadie copia valores a mano en ningún sentido.
3. **Bidireccionalidad efectiva.** El estado digital se actualiza con el físico *y* el físico
   responde a las órdenes del digital. Es la condición que separa gemelo de sombra.
4. **Coherencia verificable.** Existe una tolerancia definida y un procedimiento para
   comprobar que ambos lados coinciden (en el laboratorio, el experimento B).
5. **Fidelidad declarada.** Se sabe qué se está representando y con qué resolución, latencia y
   error. Un gemelo que no declara su fidelidad no es auditable.
6. **Capacidad de simular.** La representación puede evolucionar con reglas propias entre
   reportes (inercia, acumulación, detección de blancos), no solo copiar el último número.

---

## 1.5. Latencia, periodo y granularidad: la fidelidad no se asume, se mide

El reporte del Arduino llega con un retraso que depende del periodo elegido y del tiempo de
transmisión. Con 9600 baudios y tramas de 10 bytes (por ejemplo `S:180,POT` + salto de línea),
cada mensaje tarda unos **10,4 ms** en el cable. Si el periodo de reporte es de 100 ms, la
representación digital va, en el mejor caso, unos 100 ms "detrás" del mundo físico, y en el
peor, 200 ms (espera del periodo más transmisión).

Esto no invalida la clasificación, pero sí obliga a declararla. En el análisis conviene
distinguir tres cosas que se confunden con facilidad:

- **Periodo de muestreo:** cada cuánto se lee el potenciómetro en el firmware.
- **Periodo de reporte:** cada cuánto se envía un mensaje `S:`.
- **Latencia de la representación:** cuánto tarda un cambio físico en verse en pantalla.

---

## 1.6. Aplicación a la situación 7 (radar de vigilancia)

El grupo implementa la situación **7: radar de vigilancia**, en la que el ángulo del
servomotor corresponde a la **orientación de la antena** y la escena muestra una pantalla de
radar con objetos en movimiento que solo se detectan cuando la antena apunta hacia ellos.

Traducido a las categorías anteriores:

| Elemento | Papel |
| --- | --- |
| Servomotor + potenciómetro | Objeto físico; el ángulo es la orientación real de la antena |
| Escena de Unity | Representación; el barrido del radar y las detecciones son el comportamiento simulado |
| `S:<angulo>,<fuente>` | Flujo físico → digital (automático) |
| `A:<angulo>` desde un control de la escena | Flujo digital → físico (automático) |
| Política de arbitraje | Regla que decide qué mando prevalece cuando ambos están activos |

Con ambos flujos automáticos, el sistema **es un gemelo digital** según Kritzinger. Si se
desconectara el envío de comandos desde Unity (por ejemplo, dejando la escena solo como
visualizador), pasaría a ser una **sombra digital**, y si además la actualización se hiciera a
mano, un **modelo digital**. Esa progresión es exactamente lo que pide la pregunta 3 de
análisis.

**Un matiz que vale puntos:** el Arduino reporta el **ángulo ordenado**, no el medido. Durante
el movimiento progresivo el servo va por detrás de la orden, y si algo lo bloquea el reporte
sigue siendo optimista. La representación puede entonces mostrar un estado falso aunque el
flujo sea bidireccional y automático. Es decir: **la clasificación como gemelo depende del
flujo de datos; la calidad del gemelo depende de si el dato representa el estado real**. Ambas
cosas se discuten por separado en el análisis (pregunta 1).

---

## 1.7. Errores frecuentes al escribir el marco teórico

| Error | Por qué es un error |
| --- | --- |
| "Un gemelo digital es una réplica 3D de un objeto" | Describe un modelo, no el criterio de intercambio de datos. |
| "Como Unity se actualiza solo, ya es gemelo digital" | Falta el otro sentido: si no se envían comandos automáticamente, es una sombra. |
| Usar "sombra digital" como sinónimo de "gemelo digital" | Es justo la confusión que la rúbrica penaliza. |
| Citar solo páginas comerciales | La rúbrica pide al menos tres fuentes **técnicas o académicas**. |
| No declarar la convención terminológica | Si se usa otra definición, hay que decir cuál y por qué. |

---

## 1.8. Preguntas de autoevaluación

1. Un sensor envía datos automáticamente a un panel, y un operario cambia el actuador a mano
   leyendo ese panel. ¿Qué categoría es y por qué?
2. ¿Un gemelo digital tiene que ser necesariamente un modelo 3D? Justifique con la definición
   de Kritzinger.
3. Si el firmware reporta el ángulo ordenado en lugar del medido, ¿deja de ser gemelo digital?
   Separe la respuesta en "clasificación por flujos" y "fidelidad".
4. ¿Qué evidencia experimental demostraría que los dos flujos son automáticos y coherentes?
5. ¿Qué diferencia hay entre periodo de muestreo, periodo de reporte y latencia?

---

## 1.9. Fuentes consultadas

1. **Kritzinger, W., Karner, M., Traar, G., Henjes, J. y Sihn, W. (2018).** *Digital Twin in
   manufacturing: A categorical literature review and classification.* IFAC-PapersOnLine,
   51(11), 1016–1022.
   <https://doi.org/10.1016/j.ifacol.2018.08.474>
   → Origen de la clasificación modelo / sombra / gemelo según los flujos de datos. Es la
   fuente que conviene citar en el póster para la definición operativa.

2. **Glaessgen, E. H. y Stargel, D. (2012).** *The Digital Twin Paradigm for Future NASA and
   U.S. Air Force Vehicles.* 53rd AIAA/ASME/ASCE/AHS/ASC Structures, Structural Dynamics and
   Materials Conference, Honolulu.
   <https://ntrs.nasa.gov/citations/20120005992>
   → Definición formal desde la ingeniería aeroespacial; útil para la noción de simulación
   multiphísica alimentada por sensores.

3. **Grieves, M. y Vickers, J. (2017).** *Digital Twin: Mitigating Unpredictable, Undesirable
   Emergent Behavior in Complex Systems.* En: Kahlen, F.-J., Flumerfelt, S. y Alves, A. (eds.),
   *Transdisciplinary Perspectives on Complex Systems*, Springer, pp. 85–113.
   <https://link.springer.com/chapter/10.1007/978-3-319-38756-7_4>
   → Origen conceptual del término y su relación con la gestión del ciclo de vida.

4. **Tao, F., Zhang, H., Liu, A. y Nee, A. Y. C. (2019).** *Digital Twin in Industry:
   State-of-the-Art.* IEEE Transactions on Industrial Informatics, 15(4), 2405–2415.
   <https://doi.org/10.1109/TII.2018.2873186>
   → Modelo de cinco dimensiones (físico, virtual, datos, servicios, conexión); sirve para
   estructurar la metodología del póster.

5. **IBM Institute for Business Value.** *Digital twins: The art of the possible in product
   development.* <https://www.ibm.com/thought-leadership/institute-business-value/en-us/report/digital-twin>
   → Fuente industrial con casos de uso; útil para el contexto, no para la definición técnica.

---

**Siguiente guía:** [Servomotores](./02-servomotores.md)
