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
    echo -e "${GREEN}Installing dependencies (Node.js, SQLite, Git, Docker)...${NC}"
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
  "version": "2.0.0",
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

    # Create main app file with Login, Register, Admin and Member Dashboards
    cat << 'EOF' > app.js
const express = require('express');
const session = require('express-session');
const bodyParser = require('body-parser');
const sqlite3 = require('sqlite3').verbose();
const bcrypt = require('bcryptjs');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 50000;

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

// Middleware for Auth
const isAuthenticated = (req, res, next) => {
    if (req.session.user) return next();
    res.redirect('/login');
};

const isAdmin = (req, res, next) => {
    if (req.session.user && req.session.user.role === 'admin') return next();
    res.status(403).send('Access Denied. <a href="/dashboard">Go Back</a>');
};

// Root route redirects to Login
app.get('/', (req, res) => {
    res.redirect('/login');
});

// Login Page
app.get('/login', (req, res) => {
    res.send(`
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <title>CJH Panel - Login</title>
            <style>
                body { background: #0f172a; color: #f8fafc; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; }
                .card { background: #1e293b; padding: 40px; border-radius: 12px; box-shadow: 0 10px 25px rgba(0,0,0,0.5); width: 350px; }
                h2 { text-align: center; margin-bottom: 24px; color: #38bdf8; }
                input { width: 100%; padding: 12px; margin: 10px 0; background: #0f172a; border: 1px solid #334155; color: white; border-radius: 6px; box-sizing: border-box; }
                button { width: 100%; padding: 12px; background: #38bdf8; border: none; color: #0f172a; border-radius: 6px; font-weight: bold; cursor: pointer; margin-top: 10px; }
                button:hover { background: #0ea5e9; }
                .links { text-align: center; margin-top: 15px; font-size: 14px; }
                .links a { color: #38bdf8; text-decoration: none; }
                .links a:hover { text-decoration: underline; }
            </style>
        </head>
        <body>
            <div class="card">
                <h2>CJH Panel Login</h2>
                <form action="/login" method="POST">
                    <input type="text" name="username" placeholder="Username" required>
                    <input type="password" name="password" placeholder="Password" required>
                    <button type="submit">Login</button>
                </form>
                <div class="links">
                    <p>Don't have an account? <a href="/register">Register here</a></p>
                </div>
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
            res.send(`<script>alert('Invalid username or password!'); window.location.href='/login';</script>`);
        }
    });
});

// Register Page
app.get('/register', (req, res) => {
    res.send(`
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <title>CJH Panel - Register</title>
            <style>
                body { background: #0f172a; color: #f8fafc; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; }
                .card { background: #1e293b; padding: 40px; border-radius: 12px; box-shadow: 0 10px 25px rgba(0,0,0,0.5); width: 350px; }
                h2 { text-align: center; margin-bottom: 24px; color: #38bdf8; }
                input { width: 100%; padding: 12px; margin: 10px 0; background: #0f172a; border: 1px solid #334155; color: white; border-radius: 6px; box-sizing: border-box; }
                button { width: 100%; padding: 12px; background: #38bdf8; border: none; color: #0f172a; border-radius: 6px; font-weight: bold; cursor: pointer; margin-top: 10px; }
                button:hover { background: #0ea5e9; }
                .links { text-align: center; margin-top: 15px; font-size: 14px; }
                .links a { color: #38bdf8; text-decoration: none; }
                .links a:hover { text-decoration: underline; }
            </style>
        </head>
        <body>
            <div class="card">
                <h2>Create Account</h2>
                <form action="/register" method="POST">
                    <input type="text" name="username" placeholder="Choose Username" required>
                    <input type="password" name="password" placeholder="Choose Password" required>
                    <button type="submit">Register</button>
                </form>
                <div class="links">
                    <p>Already have an account? <a href="/login">Login here</a></p>
                </div>
            </div>
        </body>
        </html>
    `);
});

app.post('/register', async (req, res) => {
    const { username, password } = req.body;
    try {
        const hashedPassword = await bcrypt.hash(password, 10);
        db.run(`INSERT INTO users (username, password, role) VALUES (?, ?, 'member')`, [username, hashedPassword], (err) => {
            if (err) {
                res.send(`<script>alert('Username already exists!'); window.location.href='/register';</script>`);
            } else {
                res.send(`<script>alert('Registration successful! Please login.'); window.location.href='/login';</script>`);
            }
        });
    } catch (e) {
        res.redirect('/register');
    }
});

// Member Dashboard
app.get('/dashboard', isAuthenticated, (req, res) => {
    res.send(`
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <title>Member Dashboard - CJH Panel</title>
            <style>
                body { background: #0f172a; color: #f8fafc; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; padding: 20px; }
                .container { max-width: 900px; margin: auto; background: #1e293b; padding: 30px; border-radius: 12px; box-shadow: 0 4px 15px rgba(0,0,0,0.4); }
                h1 { color: #38bdf8; }
                .btn { display: inline-block; padding: 10px 20px; background: #ef4444; color: white; text-decoration: none; border-radius: 6px; margin-top: 20px; font-weight: bold; }
                .btn:hover { background: #dc2626; }
            </style>
        </head>
        <body>
            <div class="container">
                <h1>Welcome, ${req.session.user.username} (Member)</h1>
                <p>Yeh aapka Member Dashboard hai. Yahan aapke active VMs, Minecraft servers, aur settings show honge.</p>
                <hr style="border-color: #334155;">
                <a href="/logout" class="btn">Logout</a>
            </div>
        </body>
        </html>
    `);
});

// Admin Panel
app.get('/admin', isAuthenticated, isAdmin, (req, res) => {
    res.send(`
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <title>Admin Panel - CJH Panel</title>
            <style>
                body { background: #0f172a; color: #f8fafc; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; padding: 20px; }
                .container { max-width: 900px; margin: auto; background: #1e293b; padding: 30px; border-radius: 12px; box-shadow: 0 4px 15px rgba(0,0,0,0.4); }
                h1 { color: #38bdf8; }
                .btn { display: inline-block; padding: 10px 20px; background: #ef4444; color: white; text-decoration: none; border-radius: 6px; margin-top: 20px; font-weight: bold; }
                .btn:hover { background: #dc2626; }
            </style>
        </head>
        <body>
            <div class="container">
                <h1>Admin Control Panel</h1>
                <p>Yahan se aap VMs create kar sakte hain, Nodes manage kar sakte hain, themes, logo aur settings badal sakte hain.</p>
                <hr style="border-color: #334155;">
                <a href="/logout" class="btn">Logout</a>
            </div>
        </body>
        </html>
    `);
});

// Logout Route
app.get('/logout', (req, res) => {
    req.session.destroy(() => {
        res.redirect('/login');
    });
});

app.listen(PORT, '0.0.0.0', () => {
    console.log(`CJH Panel running on port ${PORT}`);
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

    clear
    echo -e "${GREEN}==========================================${NC}"
    echo -e "${GREEN} CJH Panel Installed Successfully!${NC}"
    echo -e "${GREEN} Port: 50000 (Active & Forwarded)${NC}"
    echo -e "${GREEN} Default Admin Username: admin${NC}"
    echo -e "${GREEN} Default Admin Password: admin${NC}"
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
