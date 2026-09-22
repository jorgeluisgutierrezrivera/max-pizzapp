# -*- coding: utf-8 -*-
"""Comprueba el acceso real contra Keycloak: Authorization Code + PKCE.

Recorre lo mismo que hara el navegador de recepcion y cocina —pantalla de
acceso, envio de credenciales, canje del codigo por el token— y verifica que el
token resultante dice lo que el documento promete:

  * lleva el rol del usuario, y solo el suyo;
  * lleva a la API en su audiencia;
  * vive 60 minutos (RNF-02).

Uso, con el entorno levantado y las contrasenas de demostracion establecidas:

    python pruebas/identidad/probar_acceso_pkce.py

La contrasena se lee del .env (que no se versiona) y nunca se imprime.
"""
import base64
import hashlib
import html
import http.cookiejar
import io
import json
import os
import re
import secrets
import sys
import urllib.error
import urllib.parse
import urllib.request

RAIZ = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
REALM = 'maxpizzapp'
CLIENTE = 'frontend-web'
REDIRECT = 'http://localhost:9999/callback'
VIGENCIA_ESPERADA = 3600


def entorno(clave, por_defecto=None):
    ruta = os.path.join(RAIZ, '.env')
    if os.path.exists(ruta):
        for linea in io.open(ruta, encoding='utf-8'):
            if linea.startswith(clave + '='):
                return linea.split('=', 1)[1].strip()
    if por_defecto is None:
        sys.exit('Falta %s en el .env' % clave)
    return por_defecto


KC = 'http://localhost:%s' % entorno('KEYCLOAK_PORT', '8082')


def b64url(datos):
    return base64.urlsafe_b64encode(datos).rstrip(b'=').decode()


def sin_redirecciones(tarro):
    class NoRedir(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *a, **k):
            return None  # el codigo de autorizacion viaja en la cabecera Location
    return urllib.request.build_opener(
        urllib.request.HTTPCookieProcessor(tarro), NoRedir).open


def probar(usuario, rol_esperado):
    print('\n=== %s ===' % usuario)
    verificador = b64url(secrets.token_bytes(48))
    desafio = b64url(hashlib.sha256(verificador.encode()).digest())

    tarro = http.cookiejar.CookieJar()
    abrir = sin_redirecciones(tarro)

    consulta = urllib.parse.urlencode({
        'client_id': CLIENTE, 'response_type': 'code', 'scope': 'openid',
        'redirect_uri': REDIRECT,
        'code_challenge': desafio, 'code_challenge_method': 'S256',
    })
    pagina = abrir('%s/realms/%s/protocol/openid-connect/auth?%s'
                   % (KC, REALM, consulta)).read().decode('utf-8')

    # Keycloak marca sus cookies de sesion como Secure con SameSite=None. Los
    # navegadores hacen una excepcion con localhost y las envian igual sobre
    # HTTP; un cliente HTTP no, y sin ellas el acceso falla con "Restart login
    # cookie not found". Se emula esa excepcion aqui: en produccion todo va por
    # HTTPS detras del proxy y la cuestion no existe.
    for cookie in tarro:
        cookie.secure = False

    formulario = re.search(r'action="([^"]+)"', pagina)
    if not formulario:
        sys.exit('  no se encontro el formulario de acceso')
    print('  1. pantalla de acceso servida por Keycloak')

    datos = urllib.parse.urlencode({
        'username': usuario,
        'password': entorno('KEYCLOAK_DEMO_PASSWORD'),
        'credentialId': '',
    }).encode()
    try:
        cuerpo = abrir(urllib.request.Request(
            html.unescape(formulario.group(1)), data=datos)).read().decode('utf-8', 'replace')
        sys.exit('  el acceso no se completo: %s' % (
            'credenciales rechazadas' if 'Invalid username or password' in cuerpo
            else 'no hubo redireccion'))
    except urllib.error.HTTPError as respuesta:
        destino = respuesta.headers.get('Location') or ''
    codigo = urllib.parse.parse_qs(urllib.parse.urlparse(destino).query).get('code', [None])[0]
    if not codigo:
        sys.exit('  la redireccion no trae codigo: %s' % destino[:140])
    print('  2. credenciales aceptadas, codigo de autorizacion recibido')

    datos = urllib.parse.urlencode({
        'grant_type': 'authorization_code', 'client_id': CLIENTE, 'code': codigo,
        'redirect_uri': REDIRECT, 'code_verifier': verificador,
    }).encode()
    token = json.load(urllib.request.urlopen(
        '%s/realms/%s/protocol/openid-connect/token' % (KC, REALM), data=datos))
    print('  3. codigo canjeado por token (verificador de PKCE aceptado)')

    carga = token['access_token'].split('.')[1]
    carga = json.loads(base64.urlsafe_b64decode(carga + '=' * (-len(carga) % 4)))
    roles = carga.get('realm_access', {}).get('roles', [])
    audiencia = carga.get('aud')
    audiencia = audiencia if isinstance(audiencia, list) else [audiencia]
    vigencia = carga['exp'] - carga['iat']

    print('  emisor    :', carga['iss'])
    print('  audiencia :', audiencia)
    print('  roles     :', roles)
    print('  vigencia  :', vigencia // 60, 'minutos')

    otro = 'cocina' if rol_esperado == 'recepcion' else 'recepcion'
    fallos = []
    if rol_esperado not in roles:
        fallos.append('falta el rol %s' % rol_esperado)
    if otro in roles:
        fallos.append('lleva el rol %s, que no le corresponde' % otro)
    if 'backend-api' not in audiencia:
        fallos.append('la API no figura en la audiencia')
    if vigencia != VIGENCIA_ESPERADA:
        fallos.append('la vigencia no son los 60 minutos que declara el RNF-02')
    if fallos:
        print('  RESULTADO: FALLA ->', '; '.join(fallos))
        return False
    print('  RESULTADO: correcto')
    return True


if __name__ == '__main__':
    correcto = probar('recepcion.demo', 'recepcion') & probar('cocina.demo', 'cocina')
    print('\n' + ('TODO CORRECTO' if correcto else 'HAY FALLOS'))
    sys.exit(0 if correcto else 1)
