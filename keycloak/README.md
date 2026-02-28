# Keycloak Configuration for Perfana

This directory contains Keycloak realm configuration that is automatically imported on startup.

## Realm Configuration

### perfana-realm.json

Complete realm export including:
- Realm settings and security policies
- Client configurations (perfana-web and perfana-api)
- Roles (user, admin, perfana-admin)
- Default users for testing
- Authentication flows

## Automatic Import

The realm is automatically imported when Keycloak starts using the `--import-realm` command flag in docker-compose:

```yaml
command: ["start-dev", "--import-realm"]
volumes:
  - ./keycloak/realms:/opt/keycloak/data/import
```

## Clients

### perfana-web (Public Client)
- **Client ID**: perfana-web
- **Type**: Public (PKCE-enabled)
- **URLs**: http://localhost:4000 (and dev ports 3000, 4000, 4001)
- **Grant Types**: Authorization Code with PKCE, Direct Grant
- **Usage**: Next.js frontend authentication

### perfana-api (Confidential Client)
- **Client ID**: perfana-api
- **Type**: Confidential (has secret)
- **URLs**: http://localhost:3001
- **Grant Types**: Authorization Code, Direct Grant, Service Account
- **Usage**: Backend JWT validation and service-to-service auth

## Roles

### Realm Roles
- **user** - Standard user role (default for all users)
- **admin** - Administrator role with full access
- **perfana-admin** - Perfana-specific administrator role

### Role Assignment
Roles are included in JWT tokens in the `realm_access.roles` claim:
```json
{
  "realm_access": {
    "roles": ["user", "admin"]
  }
}
```

## Default Users

### Administrator
- **Username**: admin
- **Password**: admin
- **Email**: admin@perfana.io
- **Roles**: admin, perfana-admin, user

### Test User
- **Username**: testuser
- **Password**: test123
- **Email**: test@perfana.io
- **Roles**: user

**IMPORTANT**: Change these passwords in production!

## Security Settings

### Development Mode
- SSL Required: **None** (disabled for local development)
- Registration: **Enabled** (users can self-register)
- Email Verification: **Disabled**
- Remember Me: **Enabled**

### Brute Force Protection
- **Enabled**: Yes
- **Max Login Failures**: 30
- **Wait Time**: 15 minutes after lockout
- **Quick Login Check**: 1 second

### Token Lifespans
- **Access Token**: 5 minutes (300s)
- **SSO Session Idle**: 30 minutes (1800s)
- **SSO Session Max**: 10 hours (36000s)
- **Refresh Token**: Rotating tokens

## Production Configuration

For production, update these settings via Keycloak Admin Console:

1. **Enable SSL**:
   - Set `sslRequired` to "external" or "all"
   - Configure proper certificates

2. **Disable Registration** (or add approval workflow):
   - Set `registrationAllowed` to false

3. **Enable Email Verification**:
   - Set `verifyEmail` to true
   - Configure SMTP server

4. **Update Client URLs**:
   - Use production domain URLs
   - Remove localhost URLs

5. **Change Default Passwords**:
   - Update admin and testuser passwords
   - Or remove test users entirely

6. **Configure Client Secrets**:
   - Generate new client secret for perfana-api
   - Store in environment variables

## Accessing Keycloak Admin Console

```bash
# Start Keycloak
docker compose -f docker-compose.yml up -d keycloak

# Access at http://localhost:8080
# Admin credentials from .env or defaults:
# Username: admin
# Password: admin
```

## Updating Realm Configuration

### Method 1: Export from Admin Console

1. Login to Keycloak Admin Console
2. Select "perfana" realm
3. Go to Realm Settings → Action → Partial Export
4. Select what to export
5. Download JSON and save to `realms/perfana-realm.json`

### Method 2: Manual Edit

1. Edit `perfana-realm.json` directly
2. Restart Keycloak:
```bash
docker compose -f docker-compose.yml restart keycloak
```

**Note**: Keycloak only imports realms if they don't exist. To re-import:
```bash
# Stop and remove Keycloak data
docker compose -f docker-compose.yml down
docker volume rm perfana-demo_keycloak_data

# Start fresh (will re-import realm)
docker compose -f docker-compose.yml up -d keycloak
```

## Client Credentials

### Getting perfana-api Client Secret

1. Access Keycloak Admin Console
2. Select "perfana" realm
3. Go to Clients → perfana-api
4. Go to Credentials tab
5. Copy the client secret
6. Add to `.env` file:
```bash
KEYCLOAK_CLIENT_SECRET=your-secret-here
```

## Integration Examples

### Frontend (Next.js with keycloak-js)

```typescript
import Keycloak from 'keycloak-js';

const keycloak = new Keycloak({
  url: 'http://localhost:8080',
  realm: 'perfana',
  clientId: 'perfana-web'
});

// Initialize
await keycloak.init({
  onLoad: 'login-required',
  pkceMethod: 'S256'
});

// Get token
const token = keycloak.token;
```

### Backend (NestJS)

```typescript
// Validate JWT token
@UseGuards(KeycloakAuthGuard)
@Get('profile')
async getProfile(@Request() req) {
  // req.user contains decoded JWT with roles
  return req.user;
}

// Check for admin role
if (req.user.realm_access?.roles?.includes('admin')) {
  // Admin-only logic
}
```

## Troubleshooting

### Realm Not Imported

**Check Keycloak logs**:
```bash
docker compose -f docker-compose.yml logs keycloak | grep -i import
```

**Verify volume mount**:
```bash
docker exec perfana-keycloak ls -la /opt/keycloak/data/import
```

### Client Secret Not Working

**Regenerate secret**:
1. Keycloak Admin → Clients → perfana-api
2. Credentials tab → Regenerate Secret
3. Update `.env` file with new secret
4. Restart perfana-api

### Login Redirect Issues

**Check redirect URIs**:
- Ensure client redirect URIs include your URL
- Check for trailing slashes (http://localhost:4000 vs http://localhost:4000/)
- Verify web origins match

### Token Validation Fails

**Common causes**:
1. Wrong realm in token validation
2. Token expired (check lifespans)
3. Client not configured correctly
4. Backend can't reach Keycloak (network issue)

## Testing Authentication

### Test with curl

```bash
# Get token using direct grant
curl -X POST http://localhost:8080/realms/perfana/protocol/openid-connect/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password" \
  -d "client_id=perfana-web" \
  -d "username=admin" \
  -d "password=admin"

# Response contains access_token, refresh_token, etc.
```

### Decode JWT Token

Use https://jwt.io to decode and inspect tokens:
- Check `realm_access.roles` for user roles
- Verify `exp` (expiration) timestamp
- Confirm `iss` (issuer) matches Keycloak realm

## References

- [Keycloak Documentation](https://www.keycloak.org/documentation)
- [Realm Import/Export](https://www.keycloak.org/server/importExport)
- [Client Configuration](https://www.keycloak.org/docs/latest/server_admin/#_clients)
- [PKCE Flow](https://oauth.net/2/pkce/)
