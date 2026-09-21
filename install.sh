#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Kripya is script ko root user se run karein (sudo bash install.sh).${NC}"
  exit 1
fi

show_menu() {
    clear
    echo -e "${CYAN}==========================================${NC}"
    echo -e "${CYAN}      CJH PANEL - INSTALLATION MENU${NC}[span_1](start_span)[span_1](end_span)"
    echo -e "${CYAN}==========================================${NC}"
    echo -e "1) Install CJH Panel (Main Master Node)[span_2](start_span)"[span_2](end_span)
    echo -e "2) Uninstall CJH Panel[span_3](start_span)"[span_3](end_span)
    echo -e "3) Install Daemon/Node (For Worker Servers)[span_4](start_span)"[span_4](end_span)
    echo -e "4) Exit[span_5](start_span)"[span_5](end_span)
    echo -e "${CYAN}==========================================${NC}"
    read -p "Apna option select karein [1-4]: " choice
}

install_panel() {
    echo -e "${GREEN}Dependencies install ho rahi hain (Node.js, SQLite, Git, Docker)...${NC}"
    apt-get update && apt-get upgrade -y
    apt-get install -y curl git build-essential docker.io

    # Install Node.js v18
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt-get install -y nodejs

    echo -e "${GREEN}CJH Panel directory setup ki ja rahi hai...${NC}"
    mkdir -p /var/www/cjh-panel
    cd /var/www/cjh-panel

    # Create package.json
    cat << 'EOF' > package.json
{
  "name": "cjh-panel",
  "version": "2.1.0",
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

    # Create main app file with Proxy fix and Login/Register
    cat << 'EOF' > app.js
const express = require('express');
const session = require('express-session');
const bodyParser = require('body-parser');
const sqlite3 = require('sqlite3').verbose();
const bcrypt = require('bcryptjs');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 50000;

// Proxy trust fix for CodeSandbox and cloud environments
app.set('trust proxy', true);

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
                    <p>Account nahi hai? <a href="/register">Register karein</a></p>
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
            res.send(`<script>alert('Galat username ya password hai!'); window.location.href='/login';</script>`);
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
                <h2>Account Banayein</h2>
                <form action="/register" method="POST">
                    <input type="text" name="username" placeholder="Username chuniye" required>
                    <input type="password" name="password" placeholder="Password chuniye" required>
                    <button type="submit">Register</button>
                </form>
                <div class="links">
                    <p>Pehle se account hai? <a href="/login">Login karein</a></p>
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
                res.send(`<script>alert('Yeh username pehle se maujood hai!'); window.location.href='/register';</script>`);
            } else {
                res.send(`<script>alert('Registration safal rahi! Ab login karein.'); window.location.href='/login';</script>`);
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
                <h1>Swagat hai, ${req.session.user.username} (Member)</h1>
                <p>Yeh aapka Member Dashboard hai. Yahan aapke VMs aur Minecraft servers dikhenge.</p>
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
                <p>Yahan se aap VMs create, nodes manage, themes aur settings change kar sakte hain.</p>
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
    console.log(`CJH Panel active hai port ${PORT} par`);
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
    echo -e "${GREEN} CJH Panel Safalta Purvak Install Ho Gaya!${NC}"
    echo -e "${GREEN} Port: 50000 (Active & Proxy Trusted)${NC}"
    echo -e "${GREEN} Default Admin Username: admin${NC}"
    echo -e "${GREEN} Default Admin Password: admin${NC}"
    echo -e "${GREEN}==========================================${NC}"
}

uninstall_panel() {
    echo -e "${RED}CJH Panel uninstall kiya ja raha hai...${NC}"
    systemctl stop cjh-panel
    systemctl disable cjh-panel
    rm -f /etc/systemd/system/cjh-panel.service
    rm -rf /var/www/cjh-panel
    echo -e "${GREEN}CJH Panel ko poori tarah hata diya gaya hai.${NC}"
}

install_node() {
    echo -e "${GREEN}Daemon Node dependencies install ho rahi hain...${NC}"
    apt-get update && apt-get install -y docker.io curl
    echo -e "${GREEN}Node daemon environment ready hai master panel se connect hone ke liye.${NC}"
}

# Main loop
while true; do
    show_menu
    case $choice in
        1) install_panel; exit 0 ;;
        2) uninstall_panel; exit 0 ;;
        3) install_node; exit 0 ;;
        4) exit 0 ;;
        *) echo -e "${RED}Galat option chuna hai, 1 se 4 ke beech me chunein.${NC}"; sleep 2 ;;
    esac
done
