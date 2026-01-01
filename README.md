# Nginx Reverse Proxy para HP iLO 5

Configuración de Nginx como reverse proxy para acceder a la consola HTML5 de HP iLO 5 (Integrated Lights-Out).

## Problema

Al configurar un reverse proxy para iLO 5, la consola remota HTML5 falla con el error:

```
WebSocket connection to 'wss://ilo.dominio.com/wss/ircport' failed
```

Esto ocurre porque:
1. iLO 5 es **case-sensitive** con el header `Connection: Upgrade`
2. La ruta WebSocket `/wss/` requiere configuración especial
3. iLO usa certificados autofirmados que nginx debe aceptar

## Solución

### 1. Configuración en nginx.conf

Agregar el siguiente `map` dentro del bloque `http {}`:

```nginx
http {
    # ... otras configuraciones ...

    # IMPORTANTE: "Upgrade" con U mayúscula - iLO es case-sensitive
    map $http_upgrade $connection_upgrade {
        default Upgrade;
        '' close;
    }

    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
```

### 2. Configuración del Virtual Host

Crear el archivo de configuración del sitio (ejemplo: `/etc/nginx/sites-available/ilo`):

```nginx
server {
    server_name ilo.dominio.com;

    error_log /var/log/nginx/ilo-443-error.log;
    access_log /var/log/nginx/ilo-443-access.log;

    # Configuración SSL para backend iLO (certificado autofirmado)
    proxy_ssl_verify off;
    proxy_ssl_server_name off;
    proxy_ssl_protocols TLSv1.2 TLSv1.3;

    # WebSocket para consola remota HTML5 iLO
    location ^~ /wss/ {
        proxy_pass https://192.168.13.10;
        proxy_http_version 1.1;

        # Headers WebSocket - iLO es case-sensitive con "Upgrade"
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;

        # Host del backend
        proxy_set_header Host $proxy_host;

        # Pasar todos los headers sin modificar
        proxy_pass_request_headers on;

        proxy_read_timeout 1800s;
        proxy_send_timeout 1800s;
        proxy_connect_timeout 60s;
        proxy_buffering off;
        proxy_cache off;
        proxy_request_buffering off;

        # SSL hacia el backend
        proxy_ssl_session_reuse off;
    }

    location / {
        proxy_pass https://192.168.13.10;
        proxy_http_version 1.1;

        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header Host $proxy_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Reescribir cookies del iLO para el dominio del proxy
        proxy_cookie_domain 192.168.13.10 ilo.dominio.com;
        proxy_cookie_path / /;

        proxy_buffering off;
        client_max_body_size 0;
        proxy_connect_timeout 3600s;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        send_timeout 3600s;
    }

    location /.well-known/acme-challenge/ {
        root /usr/share/nginx/html;
    }

    listen 443 ssl;
    ssl_certificate /etc/letsencrypt/live/ilo.dominio.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/ilo.dominio.com/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
}

server {
    if ($host = ilo.dominio.com) {
        return 301 https://$host$request_uri;
    }

    server_name ilo.dominio.com;
    listen 80;
    return 404;
}
```

## Instalación Rápida

### Paso 1: Editar nginx.conf

```bash
sudo nano /etc/nginx/nginx.conf
```

Agregar dentro del bloque `http {}`:

```nginx
map $http_upgrade $connection_upgrade {
    default Upgrade;
    '' close;
}
```

### Paso 2: Crear configuración del sitio

```bash
sudo nano /etc/nginx/sites-available/ilo
```

Copiar el contenido del archivo de ejemplo y modificar:
- `ilo.dominio.com` → tu dominio
- `192.168.13.10` → IP de tu iLO

### Paso 3: Habilitar el sitio

```bash
sudo ln -s /etc/nginx/sites-available/ilo /etc/nginx/sites-enabled/
```

### Paso 4: Obtener certificado SSL (opcional, con Let's Encrypt)

```bash
sudo certbot --nginx -d ilo.dominio.com
```

### Paso 5: Probar y recargar

```bash
sudo nginx -t && sudo nginx -s reload
```

## Puntos Clave

| Configuración | Valor | Razón |
|---------------|-------|-------|
| `map default` | `Upgrade` (mayúscula) | iLO es case-sensitive |
| `location ^~ /wss/` | Ruta específica | WebSocket de consola HTML5 |
| `proxy_ssl_verify` | `off` | iLO usa certificado autofirmado |
| `proxy_pass_request_headers` | `on` | No modificar headers de sesión |
| `proxy_request_buffering` | `off` | Necesario para WebSocket |
| `proxy_read_timeout` | `1800s` | Sesiones largas de consola |

## Compatibilidad

- **Nginx**: 1.18+ (probado con 1.27 y 1.29)
- **iLO**: iLO 5 (versión 3.x)
- **Servidores**: HPE ProLiant Gen10/Gen10+

## Troubleshooting

### Error 400 Bad Request

Verificar que el `map` use `Upgrade` con U mayúscula:

```bash
grep -A3 'map.*http_upgrade' /etc/nginx/nginx.conf
```

### WebSocket conecta pero no hay video

Verificar que `proxy_pass_request_headers on` esté configurado en el bloque `/wss/`.

### Consola lenta o se desconecta

Aumentar los timeouts:

```nginx
proxy_read_timeout 3600s;
proxy_send_timeout 3600s;
```

## Licencia

MIT License

## Referencias

- [RobiNET - nginx proxy for HP iLO BMC](https://blog.socha.it/2022/05/nginx-proxy-for-hp-ilo-bmc-html5.html)
- [HPE iLO 5 User Guide - Ports](https://support.hpe.com/hpesc/public/docDisplay?docId=a00105236en_us)
