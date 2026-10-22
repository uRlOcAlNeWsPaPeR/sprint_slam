#!/usr/bin/env node
// Zero-dependency place builder: turns default.project.json + src/ into build/SprintSlam.rbxlx
// using Rojo's file conventions, so the game can be opened in Studio without installing Rojo.
//
//   node tools/build-place.js            -> build/SprintSlam.rbxlx and build/manifest.json
//   node tools/build-place.js --serve    -> also serves build/manifest.json on http://localhost:34873

const fs = require("fs");
const path = require("path");
const http = require("http");

const ROOT = path.resolve(__dirname, "..");
const project = JSON.parse(fs.readFileSync(path.join(ROOT, "default.project.json"), "utf8"));

const SERVICE_CLASSES = new Set([
	"Workspace",
	"ReplicatedStorage",
	"ServerScriptService",
	"ServerStorage",
	"StarterPlayer",
	"StarterPlayerScripts",
	"StarterCharacterScripts",
	"StarterGui",
	"Lighting",
	"SoundService",
]);

const SCRIPT_SUFFIXES = [
	[".server.luau", "Script"],
	[".server.lua", "Script"],
	[".client.luau", "LocalScript"],
	[".client.lua", "LocalScript"],
	[".luau", "ModuleScript"],
	[".lua", "ModuleScript"],
];

function classifyFile(fileName) {
	for (const [suffix, className] of SCRIPT_SUFFIXES) {
		if (fileName.endsWith(suffix)) {
			return { name: fileName.slice(0, -suffix.length), className };
		}
	}
	return null;
}

// Builds a node { name, className, source?, children[], path? } from a file system path.
function nodeFromPath(name, fsPath) {
	const stat = fs.statSync(fsPath);
	if (stat.isFile()) {
		const info = classifyFile(path.basename(fsPath));
		if (!info) return null;
		return { name, className: info.className, source: fs.readFileSync(fsPath, "utf8"), children: [], path: fsPath };
	}
	const node = { name, className: "Folder", children: [], path: fsPath };
	const entries = fs.readdirSync(fsPath).sort();
	for (const entry of entries) {
		if (entry.startsWith(".")) continue;
		const full = path.join(fsPath, entry);
		const info = classifyFile(entry);
		if (info && info.name === "init") {
			node.className = info.className;
			node.source = fs.readFileSync(full, "utf8");
			continue;
		}
		if (fs.statSync(full).isDirectory()) {
			const child = nodeFromPath(entry, full);
			if (child) node.children.push(child);
		} else if (info) {
			node.children.push({
				name: info.name,
				className: info.className,
				source: fs.readFileSync(full, "utf8"),
				children: [],
				path: full,
			});
		}
	}
	return node;
}

function nodeFromTree(name, tree, parentClass) {
	if (tree.$path) {
		const node = nodeFromPath(name, path.join(ROOT, tree.$path));
		if (tree.$className) node.className = tree.$className;
		return node;
	}
	let className = tree.$className;
	if (!className) className = SERVICE_CLASSES.has(name) ? name : "Folder";
	const node = { name, className, children: [], properties: tree.$properties || {} };
	for (const [key, value] of Object.entries(tree)) {
		if (key.startsWith("$")) continue;
		node.children.push(nodeFromTree(key, value, className));
	}
	return node;
}

let referent = 0;
function xmlEscape(text) {
	return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}
function cdata(text) {
	return "<![CDATA[" + text.split("]]>").join("]]]]><![CDATA[>") + "]]>";
}
function propertyXml(name, value) {
	if (typeof value === "boolean") return `<bool name="${name}">${value}</bool>`;
	if (typeof value === "number") return `<double name="${name}">${value}</double>`;
	if (typeof value === "string") return `<string name="${name}">${xmlEscape(value)}</string>`;
	return "";
}
function itemXml(node, depth) {
	const pad = "\t".repeat(depth);
	const lines = [`${pad}<Item class="${node.className}" referent="RBX${referent++}">`, `${pad}\t<Properties>`];
	lines.push(`${pad}\t\t<string name="Name">${xmlEscape(node.name)}</string>`);
	if (node.source !== undefined) lines.push(`${pad}\t\t<ProtectedString name="Source">${cdata(node.source)}</ProtectedString>`);
	for (const [key, value] of Object.entries(node.properties || {})) {
		const xml = propertyXml(key, value);
		if (xml) lines.push(`${pad}\t\t${xml}`);
	}
	lines.push(`${pad}\t</Properties>`);
	for (const child of node.children) lines.push(itemXml(child, depth + 1));
	lines.push(`${pad}</Item>`);
	return lines.join("\n");
}

// Flat manifest for live syncing into an open Studio session: [{ path: ["ReplicatedStorage","Shared","Config"], className, source }]
function collectManifest(node, prefix, out) {
	const here = [...prefix, node.name];
	out.push({ path: here, className: node.className, source: node.source ?? null });
	for (const child of node.children) collectManifest(child, here, out);
	return out;
}

function build() {
	referent = 0;
	const roots = Object.entries(project.tree)
		.filter(([key]) => !key.startsWith("$"))
		.map(([key, value]) => nodeFromTree(key, value, "DataModel"));
	const body = roots.map((node) => itemXml(node, 1)).join("\n");
	const xml = `<roblox version="4">\n${body}\n</roblox>\n`;
	const outDir = path.join(ROOT, "build");
	fs.mkdirSync(outDir, { recursive: true });
	fs.writeFileSync(path.join(outDir, "SprintSlam.rbxlx"), xml);
	const manifest = [];
	for (const node of roots) {
		for (const child of node.children) collectManifest(child, [node.name], manifest);
	}
	fs.writeFileSync(path.join(outDir, "manifest.json"), JSON.stringify(manifest));
	const scripts = manifest.filter((entry) => entry.source !== null).length;
	console.log(`Built build/SprintSlam.rbxlx (${scripts} scripts, ${(xml.length / 1024).toFixed(1)} KB)`);
}

build();

if (process.argv.includes("--serve")) {
	const port = 34873;
	http
		.createServer((req, res) => {
			if (req.url.startsWith("/manifest.json")) {
				build();
				res.writeHead(200, { "Content-Type": "application/json" });
				res.end(fs.readFileSync(path.join(ROOT, "build", "manifest.json")));
			} else {
				res.writeHead(404);
				res.end();
			}
		})
		.listen(port, "127.0.0.1", () => console.log(`Serving manifest on http://127.0.0.1:${port}/manifest.json`));
}
