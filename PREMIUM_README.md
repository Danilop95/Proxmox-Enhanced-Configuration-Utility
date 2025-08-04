# PECU Premium - GitHub Pages Setup

Este repositorio contiene la configuración completa para PECU Premium en GitHub Pages.

## 🌟 Estructura del Proyecto

```
/
├── index.html              # Página principal con enlaces a Premium
├── premium.html            # Página de activación de licencias
├── premium.js              # JavaScript para validación de licencias
├── releases.html           # Página de releases con promoción Premium
├── styles.css              # Estilos compartidos
├── LEMON_SQUEEZY_CONFIG.md # Configuración para Lemon Squeezy
└── CNAME                   # Configuración de dominio personalizado
```

## 🎯 Características Implementadas

### ✅ Página Premium (/premium.html)
- **Validación de licencias** via API (`https://api.pecu.tools`)
- **UI profesional** con gradientes premium y animaciones
- **Formulario de activación** con formato automático de claves
- **Manejo de errores** robusto con mensajes descriptivos
- **Instrucciones claras** para usar PECU Premium
- **Sección de precios** con planes Monthly y Annual
- **FAQ completa** para resolver dudas comunes
- **Responsive design** optimizado para móviles

### ✅ JavaScript de Validación (premium.js)
- **Client-side** de validación de formato de licencias
- **Integración con API** con retry logic y timeout
- **Formateo automático** de claves de licencia
- **Manejo de URLs** con parámetros pre-rellenados
- **Copy-to-clipboard** funcionalidad
- **Error handling** comprehensivo
- **Rate limiting** y debouncing

### ✅ Integración en Páginas Existentes
- **Botón Premium** prominente en hero section
- **Banner promocional** después de Quick Start
- **Sección de soporte** actualizada con Premium CTA
- **Enlaces en releases.html** para acceso a Premium

### ✅ Configuración de Lemon Squeezy
- **Documentación completa** en `LEMON_SQUEEZY_CONFIG.md`
- **Templates de email** con URLs de activación
- **Configuración de webhooks** para sincronización
- **Formato de license keys** estandarizado
- **URLs de checkout** para ambos planes

## 🔧 Configuración Técnica

### CORS Requirements
El backend API debe permitir CORS desde:
```
https://pecu.tools
```

### Endpoints Necesarios
```
POST https://api.pecu.tools/api/v1/license/validate
GET  https://api.pecu.tools/api/v1/health
POST https://api.pecu.tools/webhooks/lemonsqueezy
```

### Formato de License Keys
```
PECU-XXXX-XXXX-XXXX-XXXX
```
- Prefijo: `PECU-`
- 4 bloques de 4 caracteres
- Caracteres permitidos: A-Z, 0-9

## 🎨 Diseño y UX

### Colores Premium
```css
--premium-gradient: linear-gradient(135deg, #667eea 0%, #764ba2 100%)
--premium-blue: #667eea
--premium-purple: #764ba2
```

### Elementos Visuales
- **Icono Corona** (`fas fa-crown`) para elementos Premium
- **Gradientes** consistentes en toda la UI
- **Badges Premium** con colores distintivos
- **Animaciones sutiles** para mejor UX
- **Cards con backdrop-filter** para efecto glassmorphism

## 🚀 Flow de Usuario Completo

### 1. Descubrimiento
- Usuario visita `pecu.tools`
- Ve botón "Premium" en hero section
- Ve banner promocional después de Quick Start
- Accede desde sección de soporte

### 2. Información
- Llega a `/premium.html`
- Ve características premium
- Compara planes Monthly vs Annual
- Lee FAQ y beneficios

### 3. Compra (Lemon Squeezy)
- Click en "Get Monthly/Annual Plan"
- Checkout en Lemon Squeezy
- Recibe email con license key
- Modal de confirmación con botón de activación

### 4. Activación
- Click en botón del email/modal
- Llega a `/premium?license=XXX&email=XXX&order_id=XXX`
- Ve licencia pre-rellenada
- Valida automáticamente o manualmente
- Ve confirmación de activación exitosa

### 5. Uso
- Ejecuta Release Selector en Proxmox
- Selecciona "P) Premium releases"
- Pega license key cuando se solicite
- Accede a releases premium y características avanzadas

## 📱 Responsive Design

### Breakpoints
- **Mobile**: < 768px
- **Tablet**: 768px - 1024px  
- **Desktop**: > 1024px

### Optimizaciones Móviles
- Stack layout en pricing cards
- Botones de ancho completo
- Font sizes escalables
- Touch-friendly form inputs
- Navegación simplificada

## 🔒 Seguridad

### Validación Client-Side
- Formato de license key
- Longitud y caracteres permitidos
- Timeout en requests
- Rate limiting visual

### Validación Server-Side
- Verificación de firma de webhooks
- Validación de hardware hash
- Rate limiting por IP
- Logs de seguridad

## 📊 Analytics y Tracking

### Events Implementados
```javascript
// Ejemplos de eventos tracking
'license_validation_success'
'license_validation_error'  
'premium_page_view'
'pricing_plan_click'
```

### Integración Sugerida
- Google Analytics 4
- Mixpanel para funnels
- PostHog para product analytics
- Custom events para business metrics

## 🔄 Mantenimiento

### Updates Regulares
- [ ] Actualizar precios en página premium
- [ ] Revisar FAQs basado en support tickets  
- [ ] Optimizar copy basado en conversiones
- [ ] Añadir nuevas características premium
- [ ] Actualizar documentación de API

### Monitoring
- [ ] Uptime de `api.pecu.tools`
- [ ] Errores de validación de licencias
- [ ] Performance de GitHub Pages
- [ ] Conversion rate de premium
- [ ] Customer satisfaction scores

## 🎯 KPIs Sugeridos

### Conversión
- Premium page visits → License purchases
- Free users → Premium trials
- Monthly → Annual upgrades
- Support → Premium conversions

### Engagement  
- License validation success rate
- Premium feature usage
- Customer support tickets
- Community feedback scores

## 🚀 Próximos Pasos

1. **Deploy** esta configuración a GitHub Pages
2. **Configurar** Lemon Squeezy según `LEMON_SQUEEZY_CONFIG.md`
3. **Implementar** backend API endpoints
4. **Probar** flow completo end-to-end
5. **Configurar** monitoring y analytics
6. **Launch** marketing campaigns

---

**🔗 Enlaces Importantes:**
- GitHub Pages: `https://pecu.tools`
- Premium Page: `https://pecu.tools/premium.html`
- API Docs: `https://api.pecu.tools/docs`
- Support: `https://discord.gg/euQTVNc2xg`
