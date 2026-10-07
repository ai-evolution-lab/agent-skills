#!/usr/bin/env node
// skills.mjs — agent-skills 管理核心。一处实现，三处入口：CLI 子命令 / dashboard 本地服务 / init 引导。
// 无第三方依赖。Windows 用 junction，macOS/Linux 用 symlink。
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import http from 'node:http';
import crypto from 'node:crypto';
import { spawnSync, spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const TOOLS = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.resolve(TOOLS, '..');
const SRC = path.join(REPO, 'skills');
const HOME = os.homedir();
const LOCK = path.join(HOME, '.agents', 'skills.lock.json');
const BAK = path.join(HOME, '.agents', 'skills.bak');
const OS = process.platform; // win32 | darwin | linux
const OS_TAG = OS === 'win32' ? 'windows' : OS === 'darwin' ? 'macos' : 'linux';

const J = (...a) => path.join(...a);
const ok = (m) => { console.log(m); };
const warn = (m) => { console.log('⚠ ' + m); };
const die = (m) => { console.error('✗ ' + m); process.exitCode = 1; };

// ---------- git ----------
function git(...args) {
  const r = spawnSync('git', ['-C', REPO, ...args], { encoding: 'utf8' });
  return { out: (r.stdout || '').trim(), err: (r.stderr || '').trim(), code: r.status };
}

// ---------- frontmatter（极简 YAML 子集：单行标量 / [a, b] / does 块列表）----------
function parseSkill(dir) {
  const f = J(dir, 'SKILL.md');
  if (!fs.existsSync(f)) return null;
  const txt = fs.readFileSync(f, 'utf8');
  const m = txt.match(/^---\r?\n([\s\S]*?)\r?\n---/);
  const meta = { name: path.basename(dir), platforms: ['windows', 'macos', 'linux'], does: [], description: '' };
  if (m) {
    let cur = null;
    for (const ln of m[1].split(/\r?\n/)) {
      let k;
      if ((k = ln.match(/^([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$/))) {
        cur = k[1];
        const v = k[2].trim();
        if (v === '') meta[cur] = [];
        else if (/^\[.*\]$/.test(v)) meta[cur] = v.slice(1, -1).split(',').map((s) => s.trim()).filter(Boolean);
        else meta[cur] = v.replace(/^["'](.*)["']$/s, '$1');
      } else if ((k = ln.match(/^\s*-\s+(.*)$/)) && Array.isArray(meta[cur]) && cur) meta[cur].push(k[1].trim());
    }
  }
  meta.platforms = Array.isArray(meta.platforms) && meta.platforms.length ? meta.platforms : ['windows', 'macos', 'linux'];
  return meta;
}
const allSkills = () =>
  fs.readdirSync(SRC, { withFileTypes: true }).filter((d) => d.isDirectory() && !d.name.startsWith('.'))
    .map((d) => parseSkill(J(SRC, d.name))).filter(Boolean).sort((a, b) => a.name.localeCompare(b.name));

// ---------- 链接目标目录（realpath 去重：win 上 .codex/.claude 等本身是通往 hub 的 junction）----------
function linkDirs() {
  const raw = [];
  const add = (p, anchor) => {
    try {
      if (fs.existsSync(p)) raw.push(p);
      else if (anchor && fs.existsSync(anchor)) { fs.mkdirSync(p, { recursive: true }); raw.push(p); }
    } catch { /* ignore */ }
  };
  add(J(HOME, '.skills'));                                        // Windows 聚合 hub（若存在）
  add(J(HOME, '.agents', 'skills'), J(HOME, '.agents'));           // 通用聚合（Mac 主用；Win 与 hub 同径时去重）
  add(J(HOME, '.codex', 'skills'), J(HOME, '.codex'));
  add(J(HOME, '.claude', 'skills'), J(HOME, '.claude'));
  add(J(HOME, '.cursor', 'skills'), J(HOME, '.cursor'));
  add(J(HOME, '.config', 'opencode', 'skills'), J(HOME, '.config', 'opencode'));
  add(J(HOME, '.openclaw', 'workspace', 'skills'), J(HOME, '.openclaw'));
  const seen = new Set(); const out = [];
  for (const d of raw) {
    const r = (() => { try { return fs.realpathSync(d); } catch { return d; } })();
    if (!seen.has(r)) { seen.add(r); out.push(d); }
  }
  return out;
}

const isLink = (st) => st.isSymbolicLink() || (typeof st.isJunction === 'function' && st.isJunction());
const safeReal = (p) => { try { return fs.realpathSync(p); } catch { return null; } };

// 每个 skill 在各目标目录的状态
function inspect(name) {
  const srcReal = safeReal(J(SRC, name));
  const res = { links: [], realdirs: [] };
  for (const d of linkDirs()) {
    const p = J(d, name);
    if (!fs.existsSync(p) && !fs.lstatSync(p, { throwIfNoEntry: false })) continue;
    const st = fs.lstatSync(p, { throwIfNoEntry: false });
    if (!st) continue;
    if (isLink(st)) {
      const real = safeReal(p);
      res.links.push({ dir: p, healthy: !!real && !!srcReal && real === srcReal });
    } else if (st.isDirectory()) res.realdirs.push(p);
  }
  return res;
}
function installed(name) {
  const r = inspect(name);
  return r.links.some((l) => l.healthy) && r.realdirs.length === 0;
}

// ---------- lock ----------
function readLock() {
  try { return JSON.parse(fs.readFileSync(LOCK, 'utf8')); } catch { return { installed: [], updatedAt: null }; }
}
function writeLock(l) {
  fs.mkdirSync(path.dirname(LOCK), { recursive: true });
  l.updatedAt = new Date().toISOString();
  fs.writeFileSync(LOCK, JSON.stringify(l, null, 2));
}

// ---------- 动词 ----------
function cmdInit() {
  fs.mkdirSync(J(HOME, '.agents'), { recursive: true });
  if (!fs.existsSync(LOCK)) writeLock(readLock());
  const dirs = linkDirs();
  ok(`仓库: ${REPO}`);
  ok(`链接目标 (${dirs.length}): ${dirs.join('  ')}`);
  ok(`平台: ${OS_TAG}   命令: skills list|add|remove|sync|push|doctor|dashboard`);
}

// 目录搬移：rename 优先，EPERM 降级（Windows 上目录常被句柄占用拒 rename）
function moveDir(from, to) {
  try { fs.renameSync(from, to); return; }
  catch (e) {
    if (e.code !== 'EPERM' && e.code !== 'EXDEV' && e.code !== 'EACCES') throw e;
    if (OS === 'win32') {
      const r = spawnSync('robocopy', [from, to, '/E', '/MOVE', '/NFL', '/NDL', '/NJH', '/NJS', '/NP'], { encoding: 'utf8' });
      if (r.status <= 7 && fs.existsSync(to)) { try { fs.rmSync(from, { recursive: true, force: true }); } catch { /* robocopy 已带走 */ } return; }
    }
    fs.cpSync(from, to, { recursive: true });
    fs.rmSync(from, { recursive: true, force: true });
  }
}

function cmdAdd(names) {
  const lock = readLock();
  if (names.includes('--all')) names = allSkills().map((s) => s.name);
  if (!names.length) return die('用法: skills add <name...> | --all');
  for (const n of names) {
    if (!fs.existsSync(J(SRC, n))) { warn(`${n}: 仓库里没有这个 skill，跳过`); continue; }
    const s = parseSkill(J(SRC, n));
    if (!s.platforms.includes(OS_TAG)) warn(`${n}: 标注仅适用 ${s.platforms.join('/')}，本机 ${OS_TAG}（仍按要求安装）`);
    let acted = 0;
    for (const d of linkDirs()) {
      const p = J(d, n);
      const st = fs.lstatSync(p, { throwIfNoEntry: false });
      if (st) {
        if (isLink(st) && safeReal(p) === safeReal(J(SRC, n))) continue;           // 已健康
        if (isLink(st)) fs.unlinkSync(p);                                           // 坏链 → 重建
        else if (st.isDirectory()) {                                                // 真实目录 → 备份后接管
          fs.mkdirSync(BAK, { recursive: true });
          const to = J(BAK, `${n}-${Date.now()}`);
          moveDir(p, to); warn(`${p} 是真实目录，已移入 ${to}`);
        } else { fs.unlinkSync(p); }
      }
      try {
        fs.mkdirSync(d, { recursive: true });
        fs.symlinkSync(J(SRC, n), p, OS === 'win32' ? 'junction' : 'dir');
        acted++;
      } catch (e) { die(`${n} → ${d}: ${e.message}`); }
    }
    if (!lock.installed.includes(n)) lock.installed.push(n);
    writeLock(lock);
    ok(`${acted > 0 ? '✔ 已安装' : '✔ 已就绪'} ${n}（${acted} 处新链接${s.platforms.includes(OS_TAG) ? '' : '，平台不符'}）`);
  }
}

function cmdRemove(names) {
  if (!names.length) return die('用法: skills remove <name...>');
  const lock = readLock();
  for (const n of names) {
    let removed = 0;
    for (const d of linkDirs()) {
      const p = J(d, n);
      const st = fs.lstatSync(p, { throwIfNoEntry: false });
      if (!st) continue;
      if (isLink(st)) { fs.unlinkSync(p); removed++; } else warn(`${p} 是真实目录，未删除（可能是本机内容）`);
    }
    lock.installed = lock.installed.filter((x) => x !== n);
    writeLock(lock);
    ok(`✘ 已卸载 ${n}（${removed} 处链接）`);
  }
}

function cmdDoctor(fix) {
  let issues = 0;
  const lock = readLock();
  for (const s of allSkills()) {
    const r = inspect(s.name);
    for (const l of r.links) if (!l.healthy) {
      issues++;
      ok(`坏链: ${l.dir} → 指向已不存在的位置${fix ? '' : '（--fix 可重建）'}`);
      if (fix) { fs.unlinkSync(l.dir); fs.symlinkSync(J(SRC, s.name), l.dir, OS === 'win32' ? 'junction' : 'dir'); ok(`  ✔ 已重建 ${l.dir}`); }
    }
    for (const p of r.realdirs) {
      issues++;
      ok(`真实目录（非链接）: ${p}${fix ? '' : '（重装 skills add 会备份接管）'}`);
    }
  }
  for (const n of lock.installed) if (!fs.existsSync(J(SRC, n))) { issues++; warn(`孤儿: lock 里记着 ${n}，但仓库已删除；用 skills remove ${n} 清记录`); }
  if (!issues) ok('✔ doctor 健康：所有链接指向仓库、无孤儿');
  return issues;
}

// ---------- AGENTS.md 同步 ----------
function agentsSync() {
  const logs = [];
  const repoF = J(REPO, 'agents', 'AGENTS.md');
  if (!fs.existsSync(repoF)) return ['(agents/AGENTS.md 不存在，跳过)'];
  const localF = J(HOME, '.agents', 'AGENTS.md');
  const a = fs.readFileSync(repoF, 'utf8');
  const b = fs.existsSync(localF) ? fs.readFileSync(localF, 'utf8') : null;
  if (b === null) { fs.mkdirSync(path.dirname(localF), { recursive: true }); fs.copyFileSync(repoF, localF); logs.push('AGENTS.md 首次部署 → ~/.agents/AGENTS.md'); }
  else if (a !== b) {
    if (fs.statSync(localF).mtimeMs > fs.statSync(repoF).mtimeMs) { fs.copyFileSync(localF, repoF); logs.push('本地 ~/.agents/AGENTS.md 更新 → 已拷回仓库（记得 push）'); }
    else { fs.copyFileSync(repoF, localF); logs.push('仓库 AGENTS.md → ~/.agents/AGENTS.md'); }
  }
  // 标记块同步（opencode / OpenClaw 各自保留专属内容，只替换 BEGIN/END shared 块）
  const blocks = [...a.matchAll(/<!-- BEGIN shared: ([a-z0-9-]+)[\s\S]*?<!-- END shared: \1[\s\S]*?-->/g)];
  const dests = [J(HOME, '.config', 'opencode', 'AGENTS.md'), J(HOME, '.openclaw', 'workspace', 'AGENTS.md')];
  for (const d of dests) {
    if (!fs.existsSync(d)) continue;
    let t = fs.readFileSync(d, 'utf8'); const before = t;
    for (const blk of blocks) {
      const id = blk[1];
      const re = new RegExp(`<!-- BEGIN shared: ${id}[\\s\\S]*?<!-- END shared: ${id}[\\s\\S]*?-->`);
      if (re.test(t)) t = t.replace(re, blk[0]); else logs.push(`⚠ ${d} 缺少标记块 ${id}，未同步`);
    }
    if (t !== before) { fs.writeFileSync(d, t); logs.push(`标记块已同步 → ${d}`); }
  }
  return logs.length ? logs : ['AGENTS.md 已是最新，无需动作'];
}

// ---------- sync / push / catalog ----------
function cmdSync() {
  const g = git('remote');
  if (g.out) {
    const p = git('pull', '--ff-only');
    if (p.code === 0) ok('✔ git pull --ff-only 完成');
    else { die(`pull 失败（可能有分叉，需人工处理）: ${p.err || p.out}`); return; }
  } else warn('仓库还没配 remote，跳过 pull（push 时自动配或先建远程仓库）');
  const lock = readLock();
  const toRelink = lock.installed.filter((n) => fs.existsSync(J(SRC, n)));
  if (toRelink.length) cmdAdd(toRelink);
  ok('— AGENTS.md —');
  for (const l of agentsSync()) ok('  ' + l);
  const fresh = allSkills().map((s) => s.name).filter((n) => !lock.installed.includes(n));
  if (fresh.length) ok(`🆕 仓库有 ${fresh.length} 个未装 skill: ${fresh.join(', ')}（skills add <name> 或 skills dashboard 选装）`);
  cmdDoctor(false);
}

function genCatalog() {
  const data = { generatedAt: new Date().toISOString(), skills: allSkills().map((s) => ({
    name: s.name, description: s.description, platforms: s.platforms, does: s.does, boundary: s.boundary || '' })) };
  fs.mkdirSync(J(REPO, 'docs'), { recursive: true });
  fs.writeFileSync(J(REPO, 'docs', 'catalog.json'), JSON.stringify(data, null, 2));
  // Pages 版页面 = 同一模板的副本（无 __BOOT__ 注入 → 自动只读画廊模式）
  fs.copyFileSync(J(TOOLS, 'dashboard.tpl.html'), J(REPO, 'docs', 'index.html'));
  return data.skills.length;
}

function cmdPush(msg) {
  const n = genCatalog();
  ok(`catalog.json 已重生成（${n} 个 skill）`);
  git('add', '-A');
  const st = git('status', '--porcelain');
  if (!st.out) return ok('✔ 没有待提交的改动');
  const files = st.out.split('\n').map((l) => l.trim().split(/\s+/).pop()).filter(Boolean);
  if (!msg) msg = `skills: update (${files.map((f) => f.split('/')[1] || f).slice(0, 6).join(', ')})`;
  const c = git('commit', '-m', msg);
  if (c.code !== 0) return die('commit 失败: ' + (c.err || c.out));
  const g = git('remote');
  if (!g.out) return warn('已本地提交，但没有配 remote，无法 push（见 README「首次配远程」）');
  const p = git('push');
  if (p.code !== 0) return die(`push 失败（认证？）: ${p.err || p.out}\n→ Windows 会弹浏览器授权；macOS 建议 brew install gh && gh auth login`);
  ok('✔ 已推送: ' + msg);
}

// ---------- 状态（CLI/dashboard 共用）----------
function buildState() {
  const lock = readLock();
  const skills = allSkills().map((s) => ({
    ...s, installed: installed(s.name), platformOk: s.platforms.includes(OS_TAG),
    links: inspect(s.name).links.map((l) => ({ dir: l.dir, healthy: l.healthy })),
    realdirs: inspect(s.name).realdirs,
  }));
  const g = git('remote');
  const d = git('status', '--porcelain');
  return {
    os: OS_TAG, repo: REPO, linkDirs: linkDirs(),
    skills,
    installedCount: skills.filter((s) => s.installed).length,
    notInstalled: skills.filter((s) => !s.installed && s.platformOk).map((s) => s.name),
    git: { hasRemote: !!g.out, dirty: !!d.out, branch: git('rev-parse', '--abbrev-ref', 'HEAD').out },
  };
}

function cmdList(json) {
  const st = buildState();
  if (json) return console.log(JSON.stringify(st, null, 2));
  const W = Math.max(...st.skills.map((s) => s.name.length));
  for (const s of st.skills) {
    const flag = s.installed ? '✔ 已装' : '✘ 未装';
    const plat = s.platformOk ? '' : ` [仅 ${s.platforms.join('/')}]`;
    console.log(`${flag}  ${s.name.padEnd(W)}  ${(s.boundary || '').slice(0, 46)}${plat}`);
  }
  console.log(`\n共 ${st.skills.length} 个，本机已装 ${st.installedCount}；未装可装: ${st.notInstalled.join(', ') || '无'}`);
}

function cmdInfo(name) {
  const s = parseSkill(J(SRC, name));
  if (!s) return die(`未找到 skill: ${name}`);
  ok(`名称:   ${s.name}`);
  ok(`平台:   ${s.platforms.join(', ')}`);
  ok(`描述:   ${s.description}`);
  ok(`能做:   ${s.does.join('；') || '-'}`);
  ok(`边界:   ${s.boundary || '-'}`);
  ok(`已装:   ${installed(name) ? '✔' : '✘'}   SKILL.md: ${s.description ? J(SRC, name, 'SKILL.md') : ''}`);
}

// ---------- dashboard 本地服务 ----------
function openBrowser(url) {
  const [cmd, args] = OS === 'win32' ? ['cmd.exe', ['/c', 'start', '""', url]] : OS === 'darwin' ? ['open', [url]] : ['xdg-open', [url]];
  try { spawn(cmd, args, { detached: true, stdio: 'ignore' }).unref(); } catch { console.log('手动打开: ' + url); }
}

function cmdDashboard(opts) {
  const token = crypto.randomBytes(8).toString('hex');
  const tplPath = J(TOOLS, 'dashboard.tpl.html');
  if (!fs.existsSync(tplPath)) return die('缺少 tools/dashboard.tpl.html');
  let last = Date.now();
  const server = http.createServer((req, res) => {
    last = Date.now();
    const u = new URL(req.url, 'http://127.0.0.1');
    const authed = u.searchParams.get('t') === token || req.headers['x-skill-token'] === token;
    const send = (code, type, body) => { res.writeHead(code, { 'content-type': type, 'cache-control': 'no-store' }); res.end(body); };
    if (u.pathname === '/favicon.ico') return send(204, 'text/plain', '');
    if (u.pathname === '/' ) {
      if (!authed) return send(403, 'text/plain', 'missing token');
      const boot = JSON.stringify({ token, state: buildState(), mode: 'local' });
      const html = fs.readFileSync(tplPath, 'utf8').replace('/*__BOOT__*/ null', boot);
      return send(200, 'text/html; charset=utf-8', html);
    }
    if (!authed) return send(401, 'application/json', '{"error":"unauthorized"}');
    if (u.pathname === '/api/state') return send(200, 'application/json', JSON.stringify(buildState()));
    if (u.pathname === '/api/action' && req.method === 'POST') {
      let body = '';
      req.on('data', (c) => { body += c; if (body.length > 1e5) req.destroy(); });
      req.on('end', () => {
        let out = [];
        try {
          const { op, names = [], msg } = JSON.parse(body || '{}');
          const log = (...a) => out.push(a.join(' '));
          const real = console.log; console.log = log;
          try {
            if (op === 'add') cmdAdd(names);
            else if (op === 'remove') cmdRemove(names);
            else if (op === 'sync') cmdSync();
            else if (op === 'push') cmdPush(msg);
            else if (op === 'doctor') cmdDoctor(true);
            else throw new Error('未知操作: ' + op);
          } finally { console.log = real; }
          send(200, 'application/json', JSON.stringify({ ok: !process.exitCode, out, state: buildState() }));
          process.exitCode = 0;
        } catch (e) { send(500, 'application/json', JSON.stringify({ ok: false, out: [String(e.message || e)] })); }
      });
      return;
    }
    send(404, 'text/plain', 'not found');
  });
  server.listen(opts.port || 0, '127.0.0.1', () => {
    const url = `http://127.0.0.1:${server.address().port}/?t=${token}`;
    ok('skills dashboard → ' + url + '  (Ctrl+C 关闭；30 分钟无操作自动退出)');
    if (!opts.noOpen) openBrowser(url);
  });
  const timer = setInterval(() => {
    if (Date.now() - last > 30 * 60 * 1000) { console.log('空闲超时，关闭 dashboard'); server.close(); clearInterval(timer); process.exit(0); }
  }, 60 * 1000);
  process.on('SIGINT', () => { server.close(); process.exit(0); });
}

// ---------- 入口 ----------
const [, , verb, ...rest] = process.argv;
const flags = rest.filter((x) => x.startsWith('--'));
const names = rest.filter((x) => !x.startsWith('--'));
const portF = flags.find((f) => f.startsWith('--port'));
switch (verb) {
  case 'init': cmdInit(); break;
  case 'list': cmdList(flags.includes('--json')); break;
  case 'status': console.log(JSON.stringify(buildState(), null, 2)); break;
  case 'info': cmdInfo(names[0]); break;
  case 'add': cmdAdd(names); break;
  case 'remove': cmdRemove(names); break;
  case 'sync': cmdSync(); break;
  case 'push': cmdPush(names.join(' ') || undefined); break;
  case 'doctor': process.exitCode = cmdDoctor(flags.includes('--fix')) ? 2 : 0; break;
  case 'gen-catalog': ok(`✔ catalog.json 已生成（${genCatalog()} 个 skill）`); break;
  case 'dashboard': cmdDashboard({ noOpen: flags.includes('--no-open'), port: portF ? Number(portF.split('=')[1]) : 0 }); break;
  default:
    console.log(`skills <verb> — agent-skills 跨设备管理
  list [--json]        全量 skill + 本机安装状态
  info <name>          作用 / 边界 / 平台详情
  add <name...>|--all  安装（建链接，本机选装记录）
  remove <name...>     卸载（只删链接，不动仓库文件）
  sync                 拉取更新 + 重链已装 + AGENTS.md 同步
  push [msg]           回推本地改动（自动重生成 catalog）
  doctor [--fix]       检查/修复链接
  dashboard            打开可视化页面（127.0.0.1 本地服务）`);
}
