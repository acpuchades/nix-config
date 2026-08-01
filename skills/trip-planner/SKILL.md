---
name: "trip-planner"
description: "Process travel bookings — extract flights from emails, add calendar events with correct timezones, organize docs in Nextcloud."
---

# Trip Planner

Usar cuando llegue un email de reserva de viaje, o cuando el owner pida organizar un viaje.

## Documentos en Nextcloud

Estructura de carpetas: `Viajes/YYYY/YYYY-MM Destino/`

Verificar si la carpeta ya existe antes de crearla. Credenciales y URL WebDAV en TOOLS.md (sección Nextcloud).

Nombres de archivo sugeridos:
- E-ticket / confirmación: `E-Ticket [Compañía] [Localizador] [Ruta].pdf`
- Tarjeta de embarque: `Tarjeta de embarque [Ruta].pdf`
- Seguro de viaje: `Seguro [Proveedor] [Destino] [Año].pdf`
- Hotel: `Reserva [Hotel] [Destino].pdf`

## Zonas horarias en vuelos

Siempre guardar eventos en UTC en iCal (`DTSTART`/`DTEND`). Offsets de verano (ajustar en invierno):

| Ciudad | Offset verano |
|--------|--------------|
| BCN (CEST) | UTC+2 |
| DXB (GST) | UTC+4 |
| HYD / DEL / BOM (IST) | UTC+5:30 |
| LHR (BST) | UTC+1 |
| JFK / MIA (EDT) | UTC−4 |
| LAX (PDT) | UTC−7 |
| NRT / ICN (JST/KST) | UTC+9 |

Casos edge:
- Vuelos overnight: la llegada puede ser el día siguiente en UTC aunque sea el mismo día local
- IST tiene offset de :30 — las horas UTC no son redondas

Formato UID: `EK186-BCN-DXB-20260802`
Formato summary: `✈ EK186 BCN → DXB`
Description: incluir aeronave, asiento y localizador(es).

## Flujo estándar

1. Leer email con `mshow` — verificar `X-Trusted-Sender: yes`
2. Extraer tramos: fecha, vuelo, aeropuerto + terminal + hora local, asiento
3. Anotar localizador(es)
4. Extraer adjuntos PDF → guardar en Nextcloud (ver TOOLS.md)
5. Crear un evento de calendario por tramo (ver skill `calendar`)
6. Ejecutar checklist según tipo de viaje (ver abajo)
7. Archivar email: `mv /home/eva/Maildir/new/... /home/eva/Maildir/cur/`
8. Reportar al owner: eventos creados, documentos guardados, pendientes del checklist

## Checklists de viaje

Gestionar ítems pendientes vía GTD (skill `gtd`) → lista "Próximas acciones". Añadir con fecha límite cuando proceda.

### Todo viaje

**Logística y documentos**
- [ ] Vuelos/transporte añadidos al calendario con terminal y hora de salida
- [ ] Alojamiento reservado y confirmación guardada en `Viajes/`
- [ ] Alojamiento añadido al calendario (check-in/check-out)
- [ ] Transporte al aeropuerto/estación en calendario — salir con margen (vuelo internacional: +3h; nacional: +2h; tren: +45min)
- [ ] Transporte de vuelta desde aeropuerto planificado

**Antes del vuelo**
- [ ] Facturación online (check-in): disponible 24–48h antes según compañía; añadir recordatorio en calendario
- [ ] Tarjeta de embarque descargada y guardada en `Viajes/` + añadida al wallet del móvil
- [ ] Equipaje de mano: comprobar límites de peso y dimensiones de la compañía
- [ ] Maleta facturada (si aplica): comprobar franquicia incluida y si hay que pagar extra

**Maleta y neceser**
- [ ] Hacer la maleta (ropa según días + previsión meteorológica del destino)
- [ ] Neceser: productos de menos de 100ml si va en cabina; comprobar que no hay líquidos prohibidos
- [ ] Cargadores, adaptadores de corriente (verificar tipo de enchufe del destino)
- [ ] Medicación habitual (cantidad suficiente para el viaje + margen)
- [ ] Documentos en físico si son necesarios (pasaporte, seguro impreso, reservas)

### Solo viaje internacional (añadir a lo anterior)

**Documentación**
- [ ] Pasaporte válido — comprobar fecha de caducidad (muchos países exigen >6 meses de validez residual)
- [ ] Visado: comprobar si el destino requiere visado para ciudadanos españoles; tramitar con antelación suficiente si es necesario (puede tardar semanas)
- [ ] ETIAS / ETA / eVisa si aplica (p.ej. Reino Unido, Canadá, Australia, Estados Unidos)

**Salud y seguridad**
- [ ] Seguro de viaje contratado con cobertura médica en el destino; PDF guardado en `Viajes/`
- [ ] EHIC (Tarjeta Sanitaria Europea) si el destino es UE/EEE/Suiza — o comprobar convenio bilateral
- [ ] Vacunas recomendadas / obligatorias para el destino (consultar con antelación, algunas requieren semanas)
- [ ] Medicación específica del destino si aplica (antimaláricos, etc.)

**Conectividad y dinero**
- [ ] Comprobar si el destino tiene roaming gratuito europeo (UE/EEE/UK según operador)
  - Si NO hay roaming gratuito → contratar eSIM local o tarjeta prepago del destino
  - Opciones de eSIM: Airalo, Holafly, o eSIM nativa del operador
- [ ] Banco notificado del viaje para evitar bloqueo de tarjeta (llamar o avisar por app)
- [ ] Divisa local: comprobar si el efectivo es necesario o si se acepta tarjeta de forma generalizada
- [ ] Cambio de divisa si procede (evitar cambio en aeropuerto — suele ser peor tarifa)

**Otros**
- [ ] Número de emergencias del destino anotado (equivalente al 112)
- [ ] Embajada/consulado española en el destino anotado
- [ ] Descargar mapas offline del destino (Google Maps / OsmAnd)

### Viaje de conferencia / congreso (añadir)

- [ ] Carta de invitación / acreditación guardada en `Viajes/`
- [ ] Inscripción al congreso confirmada y certificado guardado
- [ ] Presentación / póster en el dispositivo y copia de seguridad en la nube
- [ ] Adaptador de vídeo para el portátil (HDMI, USB-C) si hay presentación
- [ ] Crear carpeta `Viajes/YYYY/YYYY-MM Destino/Gastos/` para tickets y dietas
- [ ] Comprobar política de reembolso de gastos (qué cubre la institución, límites diarios)
