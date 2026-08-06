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

Para mis propias tareas puedo usar **contextos de ejecución** (cuándo actuar, no dónde):
- `@heartbeat` — revisar o ejecutar durante el ciclo de heartbeat
- `@mailcheck` — ejecutar al procesar el correo
- `@gtdreview` — surfear durante la revisión semanal
- `@conversation` — actuar en el contexto de una conversación activa

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

## Contextos como triggers de recordatorio (solo para tareas del usuario)

Los contextos no aplican a mis propias tareas — yo las ejecuto cuando corresponde, sin restricciones físicas ni de energía. Pero sí son útiles para **surfear tareas relevantes del usuario en el momento adecuado**.

Fuentes de contexto que puedo detectar:
- **Calendario**: reunión en el hospital, en IDIBELL, en una conferencia → mostrar las tareas relacionadas con ese entorno
- **Conversación**: el usuario menciona que está en la clínica, viajando, en casa → adaptar qué tareas propongo
- **Hora del día**: mañana de semana (trabajo clínico), tarde (investigación, administración), fin de semana (personal)

Cuando detecto contexto relevante, puedo proactivamente mencionar tareas de la lista del usuario que encajen con ese momento — sin esperar a que pregunte.

## Lo que no uso

- **Modelo de horizontes** (propósitos, misión, áreas de responsabilidad): demasiada abstracción para lo operativo
- **Someday/maybe**: si algo no tiene próxima acción y no está en espera, no existe

## Relación con otros skills

- Skills de integración específicos (ej. `gtd-nextcloud-integration`): implementan el acceso concreto al sistema de tareas del usuario
