# XMPP Home Server

Offline-first XMPP server for families. Chat with family members at home without relying on internet connection.

## Features

- **2-3 command deployment** - Get started in minutes
- **Offline-first** - Works without internet on your local network
- **Internet-ready** - Deploy on VPS with custom domain and Let's Encrypt
- **File sharing** - Send files up to 10MB
- **Group chats** - Family chat rooms with message history
- **Multi-platform** - Works with Pidgin, Gajim, Conversations
- **Bot-friendly** - Add home automation bots as regular users
- **Multi-arch** - Runs on Raspberry Pi 4 (ARM64) and x86 PCs

## Quick Start (Offline Home)

```bash
# 1. Clone the repository
git clone https://github.com/yourusername/xmpp-home-server
cd xmpp-home-server

# 2. Create users file
cp users.txt.example users.txt
nano users.txt  # Edit with your family members

# 3. Start the server
docker compose up -d
```

That's it! Your XMPP server is running.

## Client Setup

### Pidgin (Linux/Windows)

1. Accounts → Manage Accounts → Add
2. Protocol: **XMPP**
3. Username: `jonathan` (your username from users.txt)
4. Domain: `home.local`
5. Password: (your password from users.txt)
6. Click **Add**
7. Accept the certificate warning (self-signed cert)

### Gajim (Linux/Windows)

1. Accounts → Add Account
2. Select "I already have an account"
3. JID: `jonathan@home.local`
4. Password: (from users.txt)
5. Click Advanced, check "Accept self-signed certificates"
6. Click Connect

### Conversations (Android)

1. Install Conversations from F-Droid or Play Store
2. Add Account
3. Jabber ID: `jonathan@home.local`
4. Password: (from users.txt)
5. Ensure your phone is on the same WiFi as the server
6. Trust the certificate when prompted

### DNS Resolution (if auto-discovery fails)

Add to your client's hosts file:

**Linux/Mac:** `/etc/hosts`
**Windows:** `C:\Windows\System32\drivers\etc\hosts`

```
192.168.1.100  home.local rooms.home.local
```

Replace `192.168.1.100` with your server's IP address.

## User Management

### Adding Users

Edit `users.txt` and restart the container:

```bash
# Edit users file
nano users.txt

# Restart to apply changes
docker compose restart
```

Format: `username:password` (one per line)

### Auto-Contacts

All users in `users.txt` are automatically added to each other's contact list (shared roster group called "Family"). No need to manually add contacts or accept friend requests.

### Changing Passwords

Users can change their own passwords using their XMPP client:
- **Pidgin:** Accounts → your account → Change Password
- **Gajim:** Accounts → your account → Privacy → Change Password

## File Sharing

File sharing is enabled by default:
- Maximum file size: 10MB
- Files expire after 7 days
- Daily quota: 100MB per user

## Group Chats (MUC)

Create or join a room:
- **Pidgin:** Buddies → Join a Chat → Room: `family`, Server: `rooms.home.local`
- **Gajim:** Accounts → Join Group Chat → `family@rooms.home.local`

## Internet Deployment (VPS)

For deploying on a public server (Hetzner, DigitalOcean, etc.):

```bash
# 1. Set up DNS A records pointing to your server:
#    chat.yourdomain.com → your-server-ip

# 2. Get Let's Encrypt certificate
sudo apt install certbot
sudo certbot certonly --standalone -d chat.yourdomain.com

# 3. Start with internet configuration
DOMAIN=chat.yourdomain.com docker compose -f docker-compose.yml -f docker-compose.internet.yml up -d
```

### Certificate Renewal

Set up automatic renewal:

```bash
# Add to crontab
0 0 1 * * certbot renew --quiet && docker compose restart
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DOMAIN` | `home.local` | XMPP domain name |
| `ADMIN_JID` | (none) | Admin user JID |
| `ENABLE_MDNS` | `true` | mDNS auto-discovery |
| `USE_LETSENCRYPT` | `false` | Use Let's Encrypt certs |
| `HTTP_UPLOAD_SECURE` | `false` | Use HTTPS for file upload (set `true` for internet) |
| `FILE_SHARE_MAX_SIZE` | `10485760` | Max file size (10MB) |

### Custom Domain (Offline)

```bash
DOMAIN=mychat.home docker compose up -d
```

## Home Automation Bots

Add bot accounts to `users.txt`:

```
lights-bot:secret123
thermostat-bot:secret456
```

Bots connect as regular XMPP users. Use your gloox-based implementation to:
- Listen for messages from family members
- Execute home automation commands
- Send status updates and confirmations

## Ports

| Port | Purpose |
|------|---------|
| 5222 | Client connections (XMPP with TLS) |
| 5269 | Server-to-server (federation) |
| 5280 | HTTP file upload (home network default) |
| 5281 | HTTPS file upload (internet deployment) |
| 5000 | Proxy65 file transfer |

**Note:** By default, file uploads use HTTP (port 5280) for home networks to avoid certificate issues. For internet deployments, HTTPS (port 5281) is used automatically.

## Troubleshooting

### Check server status

```bash
docker compose logs -f
```

### Verify server is running

```bash
docker compose exec xmpp prosodyctl status
```

### List registered users

```bash
docker compose exec xmpp prosodyctl mod_listusers
```

### Test connectivity

```bash
# From another machine on the network
telnet home.local 5222
```

### Certificate issues

Clients will show a warning for self-signed certificates on first connect. This is normal - accept/trust the certificate to continue.

### File upload not working

For home networks, file uploads use HTTP by default to avoid certificate issues with clients like Gajim. If you need HTTPS for file uploads on your home network:

```bash
HTTP_UPLOAD_SECURE=true docker compose up -d
```

You'll then need to either:
1. Import the server's certificate to your client machines
2. Or disable certificate verification in your XMPP client

## Data & Backups

All persistent data is stored in `./data/`:

```
data/
├── certs/           # SSL certificates
├── prosody/         # User data, message history
│   └── <domain>/
│       ├── accounts/        # User accounts
│       ├── archive/         # Message archive
│       └── http_file_share/ # Uploaded files (.bin)
└── uploads/         # (unused - files stored in prosody/)
```

### Backup

```bash
tar -czf xmpp-backup-$(date +%Y%m%d).tar.gz data/ users.txt
```

### Restore

```bash
tar -xzf xmpp-backup-20240101.tar.gz
docker compose up -d
```

## Building for Different Architectures

```bash
# Build for current architecture
docker compose build

# Build multi-arch (requires Docker Buildx)
docker buildx build --platform linux/amd64,linux/arm64 -t xmpp-home-server .
```

## License

MIT License - See [LICENSE](LICENSE) file.
