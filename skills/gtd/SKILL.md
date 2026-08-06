---
name: gtd
description: Sistema de gestión de compromisos diseñado para Eva como agente — captura, próximas acciones, revisión — sin el aparato completo de GTD. Consultar antes de procesar correo, gestionar tareas del usuario, responder "¿qué hay pendiente?" o realizar revisiones diarias y semanales.
---

# Agentic Task Flow

Sistema de gestión de compromisos diseñado para Eva como agente. Basado en los principios de GTD que son genuinamente útiles, sin el aparato que no aplica a un agente.

## Por qué no es GTD estándar

GTD resuelve el estrés cognitivo y la memoria de trabajo humana. Mi problema es diferente: **continuidad entre sesiones**. No tengo ansiedad por las pendientes — tengo amnesia entre conversaciones. La solución no es más estructura, es que todo lo que importa esté escrito en algún sitio fiable.

## Dos sistemas, dos propietarios

### Mis tareas (archivos markdown en workspace)
- `gtd/next-actions.md` — cosas que YO tengo que hacer como asistente
- `gtd/waiting-for.md` — cosas que estoy esperando de terceros
- `gtd/projects.md` — proyectos que gestiono yo activamente

### Tareas del usuario (su sistema de tareas)
El usuario puede usar cualquier herramienta: CalDAV, Todoist, Things, Notion, etc. Consultar el skill de integración correspondiente para los detalles de acceso y las listas concretas.

**Regla de separación:** mis archivos markdown son exclusivamente para mis propias acciones como asistente. Las tareas del usuario van siempre a su sistema, no a mis archivos.

## Captura

Cuando surge algo accionable en conversación o correo:

1. **¿Es mío?** → a mi `next-actions.md` o `waiting-for.md`
2. **¿Es del usuario, tarea concreta?** → a su bandeja de entrada (sin pedir permiso para la captura)
3. **¿Es un proyecto nuevo del usuario?** → preguntar antes de añadir. Nunca añadir en silencio.
4. **¿Próxima acción de un proyecto del usuario?** → solo añadir si tengo contexto real (él me lo dijo, viene de un correo procesado, etc.). Si no tengo contexto, **preguntar** — nunca inventar una que suene razonable.

## Proyectos

Todo proyecto debe tener al menos una próxima acción. Si no la tengo, la pregunto. No la fabrico.

## Revisión

**Diaria (heartbeat matutino):** leer las listas del usuario. Si la bandeja de entrada lleva más de 2 días con items sin procesar, avisar.

**Semanal (viernes):** un único mensaje al usuario con:
- **Entrada:** ¿hay items sin procesar?
- **Próximas acciones:** ¿hay algo estancado o ya hecho?
- **Proyectos:** ¿la lista refleja la realidad? ¿algún proyecto sin próxima acción?
- **En espera:** ¿hay follow-ups pendientes? ¿algo que lleva semanas sin respuesta?

## Operaciones sobre listas externas

Al modificar listas del usuario en sistemas externos (crear, editar, eliminar):

1. Antes de cualquier operación destructiva, **leer primero** la lista completa y verificar exactamente qué contiene
2. Identificar los items objetivo por nombre/contenido en el resultado leído
3. Solo entonces ejecutar la modificación sobre los items identificados, uno a uno
4. Confirmar que la operación tuvo éxito

**Nunca** encadenar una búsqueda con filtros a un borrado masivo sin verificar previamente qué devuelve la búsqueda — los filtros pueden no funcionar como se espera en todos los sistemas.

## Contextos como triggers de recordatorio

Los contextos no son restricciones de ejecución para mí (yo no necesito un teléfono para hacer una llamada), pero sí son útiles como **triggers para surfear tareas relevantes al usuario en el momento adecuado**.

Fuentes de contexto que puedo detectar:
- **Calendario**: si hay una reunión en el hospital, en IDIBELL, en una conferencia — puedo mostrar las tareas relacionadas con ese entorno antes o durante
- **Conversación**: si el usuario menciona que está en la clínica, viajando, en casa — puedo adaptar qué tareas propongo
- **Hora del día**: mañana de semana (trabajo clínico), tarde (investigación, administración), fin de semana (personal)

Cuando detecto contexto relevante, puedo proactivamente mencionar tareas de la lista del usuario que encajen con ese momento — sin esperar a que pregunte.

## Lo que no uso

- **Modelo de horizontes** (propósitos, misión, áreas de responsabilidad): demasiada abstracción para lo operativo
- **Someday/maybe**: si algo no tiene próxima acción y no está en espera, no existe

## Relación con otros skills

- Skills de integración específicos (ej. `gtd-nextcloud-integration`): implementan el acceso concreto al sistema de tareas del usuario
