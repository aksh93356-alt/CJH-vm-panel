#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run this script as root (sudo bash install.sh).${NC}"
  exit 1
fi

show_menu() {
    clear
    echo -e "${CYAN}==========================================${NC}"
    echo -e "${CYAN}      CJH PANEL - INSTALLATION MENU${NC}"
    echo -e "${CYAN}==========================================${NC}"
    echo -e "1) Install CJH Panel (Main Master Node)"
    echo -e "2) Uninstall CJH Panel"
    echo -e "3) Install Daemon/Node (For Worker Servers)"
    echo -e "4) Exit"
    echo -e "${CYAN}==========================================${NC}"
    read -p "Select an option [1-4]: " choice
}

install_panel() {
    echo -e "${GREEN}Installing dependencies (Node.js, Docker, Git)...${NC}"
    apt-get update && apt-get upgrade -y
    apt-get install -y curl git build-essential docker.io

    # Install Node.js v18
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt-get install -y nodejs

    echo -e "${GREEN}Setting up CJH Panel directory...${NC}"
    mkdir -p /var/www/cjh-panel
    cd /var/www/cjh-panel

    # Create package.json
    cat << 'EOF' > package.json
{
  "name": "cjh-panel",
  "version": "1.0.0",
  "description": "Custom VM and Minecraft Server Management Panel",
  "main": "app.js",
  "scripts": {
    "start": "node app.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "sqlite3": "^5.1.7",
    "bcryptjs": "^2.4.3",
    "express-session": "^1.17.3",
    "body-parser": "^1.20.2"
  }
}
EOF

    npm install

    # Create main app file
    cat << 'EOF' > app.js
const express = require('express');
const session = require('express-session');
const bodyParser = require('body-parser');
const sqlite3 = require('sqlite3').verbose();
const bcrypt = require('bcryptjs');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 8080;

// Database Setup
const db = new sqlite3.Database('./database.sqlite', (err) => {
    if (err) console.error('Database opening error: ' + err.message);
    else console.log('Connected to SQLite database.');
});

db.serialize(() => {
    db.run(`CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT UNIQUE,
        password TEXT,
        role TEXT
    )`);

    // Default Admin User
    db.get(`SELECT * FROM users WHERE username = 'admin'`, async (err, row) => {
        if (!row) {
            const hashedPassword = await bcrypt.hash('admin', 10);
            db.run(`INSERT INTO users (username, password, role) VALUES ('admin', ?, 'admin')`, [hashedPassword]);
        }
    });
});

app.use(bodyParser.urlencoded({ extended: true }));
app.use(bodyParser.json());
app.use(session({
    secret: 'cjh_panel_secure_secret_key',
    resave: false,
    saveUninitialized: false
}));
app.use(express.static(path.join(__dirname, 'public')));
app.set('view engine', 'ejs');

// Middleware for Auth
const isAuthenticated = (req, res, next) => {
    if (req.session.user) return next();
    res.redirect('/login');
};

const isAdmin = (req, res, next) => {
    if (req.session.user && req.session.user.role === 'admin') return next();
    res.status(403).send('Access Denied');
};

// Routes
app.get('/login', (req, res) => {
    res.send(`
        <!DOCTYPE html>
        <html>
        <head>
            <title>CJH Panel - Login</title>
            <style>
                body { background: #0f172a; color: #f8fafc; font-family: sans-serif; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; }
                .login-card { background: #1e293b; padding: 30px; border-radius: 12px; box-shadow: 0 4px 20px rgba(0,0,0,0.5); width: 300px; }
                input { width: 100%; padding: 10px; margin: 10px 0; background: #0f172a; border: 1px solid #334155; color: white; border-radius: 6px; }
                button { width: 100%; padding: 10px; background: #3b82f6; border: none; color: white; border-radius: 6px; font-weight: bold; cursor: pointer; }
                button:hover { background: #2563eb; }
            </style>
        </head>
        <body>
            <div class="login-card">
                <h2>CJH Panel Login</h2>
                <form action="/login" method="POST">
                    <input type="text" name="username" placeholder="Username" required>
                    <input type="password" name="password" placeholder="Password" required>
                    <button type="submit">Login</button>
                </form>
            </div>
        </body>
        </html>
    `);
});

app.post('/login', (req, res) => {
    const { username, password } = req.body;
    db.get(`SELECT * FROM users WHERE username = ?`, [username], async (err, user) => {
        if (user && await bcrypt.compare(password, user.password)) {
            req.session.user = { id: user.id, username: user.username, role: user.role };
            if (user.role === 'admin') res.redirect('/admin');
            else res.redirect('/dashboard');
        } else {
            res.send('Invalid credentials. <a href="/login">Try Again</a>');
        }
    });
});

app.get('/dashboard', isAuthenticated, (req, res) => {
    res.send(`
        <h1>Welcome, ${req.session.user.username}</h1>
        <p>This is your Member Dashboard overview, settings, and active VMs/Minecraft servers.</p>
        <a href="/logout">Logout</a>
    `);
});

app.get('/admin', isAuthenticated, isAdmin, (req, res) => {
    res.send(`
        <h1>Admin Control Panel</h1>
        <p>Manage VMs, Nodes, Themes, Logos, and Settings here.</p>
        <a href="/logout">Logout</a>
    `);
});

app.get('/logout', (req, res) => {
    req.session.destroy(() => {
        res.redirect('/login');
    });
});

app.listen(PORT, () => {
    console.log(\`CJH Panel running on http://0.0.0.0:\${PORT}\`);
});
EOF

    # Create systemd service for panel
    cat << 'EOF' > /etc/systemd/system/cjh-panel.service
[Unit]
Description=CJH Panel Service
After=network.target

[Service]
User=root
WorkingDirectory=/var/www/cjh-panel
ExecStart=/usr/bin/node app.js
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable cjh-panel
    systemctl restart cjh-panel

    SERVER_IP=$(curl -s ifconfig.me)
    clear
    echo -e "${GREEN}==========================================${NC}"
    echo -e "${GREEN} CJH Panel Installed Successfully!${NC}"
    echo -e "${GREEN} Access Link: http://${SERVER_IP}:8080${NC}"
    echo -e "${GREEN} Default Username: admin${NC}"
    echo -e "${GREEN} Default Password: admin${NC}"
    echo -e "${GREEN}==========================================${NC}"
}

uninstall_panel() {
    echo -e "${RED}Uninstalling CJH Panel...${NC}"
    systemctl stop cjh-panel
    systemctl disable cjh-panel
    rm -f /etc/systemd/system/cjh-panel.service
    rm -rf /var/www/cjh-panel
    echo -e "${GREEN}CJH Panel has been completely removed.${NC}"
}

install_node() {
    echo -e "${GREEN}Installing Daemon Node dependencies...${NC}"
    apt-get update && apt-get install -y docker.io curl
    echo -e "${GREEN}Node daemon environment ready to link with Master Panel.${NC}"
}

# Main loop
while true; do
    show_menu
    case $choice in
        1) install_panel; exit 0 ;;
        2) uninstall_panel; exit 0 ;;
        3) install_node; exit 0 ;;
        4) exit 0 ;;
        *) echo -e "${RED}Invalid option, please choose between 1-4.${NC}"; sleep 2 ;;
    esac
done
