'use strict';

// Usage: node splice-blocks.js <plugin root> <base config.toml> <light|dark>

const fs = require('node:fs');
const path = require('node:path');

const [root, base, appearance] = process.argv.slice(2);
const managed = require(path.join(root, 'lib', 'managed-config'));

// Tab-bar keys belong to [ui].
const ui = /^\[ui\]\s*$/m;
const text = fs.readFileSync(base, 'utf8');
const tabBar = managed.block();
const withTabBar = ui.test(text) ? text.replace(ui, `$&\n${tabBar}`) : `${text}\n[ui]\n${tabBar}\n`;

process.stdout.write(`${withTabBar}\n${managed.sidebarBlock(appearance)}\n`);
