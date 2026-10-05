const fs = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');

// Real ZIP records let the tests vary host attributes, Unicode names and local
// headers independently. No extractor/validator responses are mocked.
const table = Array.from({ length: 256 }, (_, value) => {
  for (let bit = 0; bit < 8; bit++) value = (value >>> 1) ^ ((value & 1) ? 0xedb88320 : 0);
  return value >>> 0;
});
function crc32(data) {
  let crc = 0xffffffff;
  for (const byte of data) crc = (crc >>> 8) ^ table[(crc ^ byte) & 0xff];
  return (crc ^ 0xffffffff) >>> 0;
}
function zip(destination, entries) {
  const locals = [], central = [];
  let offset = 0;
  for (const entry of entries) {
    const name = Buffer.from(`fixture/${entry.name}`);
    const localName = Buffer.from(`fixture/${entry.localName ?? entry.name}`);
    const data = Buffer.isBuffer(entry.data) ? entry.data : Buffer.from(entry.data ?? 'fixture\n');
    const compressed = zlib.deflateRawSync(data, { level: 9 });
    const crc = crc32(data) ^ (entry.badCRC ? 1 : 0);
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50);
    local.writeUInt16LE(20, 4);
    local.writeUInt16LE(0x800, 6);
    local.writeUInt16LE(8, 8);
    local.writeUInt32LE(crc >>> 0, 14);
    local.writeUInt32LE(compressed.length, 18);
    local.writeUInt32LE(data.length, 22);
    local.writeUInt16LE(localName.length, 26);
    locals.push(local, localName, compressed);
    const record = Buffer.alloc(46);
    record.writeUInt32LE(0x02014b50);
    record.writeUInt16LE(((entry.host ?? 3) << 8) | 20, 4);
    record.writeUInt16LE(20, 6);
    record.writeUInt16LE(0x800, 8);
    record.writeUInt16LE(8, 10);
    record.writeUInt32LE(crc >>> 0, 16);
    record.writeUInt32LE(compressed.length, 20);
    record.writeUInt32LE(data.length, 24);
    record.writeUInt16LE(name.length, 28);
    record.writeUInt32LE(((entry.mode ?? 0o100644) << 16) >>> 0, 38);
    record.writeUInt32LE(offset, 42);
    central.push(record, name);
    offset += local.length + localName.length + compressed.length;
  }
  const directory = Buffer.concat(central);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50);
  end.writeUInt16LE(entries.length, 8);
  end.writeUInt16LE(entries.length, 10);
  end.writeUInt32LE(directory.length, 12);
  end.writeUInt32LE(offset, 16);
  fs.writeFileSync(destination, Buffer.concat([...locals, directory, end]));
}
const directory = process.argv[2];
fs.mkdirSync(directory, { recursive: true });
const core = version => [
  { name: 'VERSION', data: `${version}\n` },
  { name: 'LICENSE', data: 'MIT License\n' },
  { name: 'install.sh', data: '#!/bin/bash\nexit 0\n', mode: 0o100755 },
  { name: 'bin/routine', data: '#!/bin/bash\nexit 0\n', mode: 0o100755 },
];
const create = (name, entries) => zip(path.join(directory, `${name}.zip`), entries);
create('korean', [...core('2.0.0'), ...['설치.md', '설정.md', '설치 방법.txt', '설정 방법.txt'].map(name => ({ name }))]);
create('no-directories', core('2.0.0'));
create('duplicate', [...core('2.0.0'), { name: 'install.sh' }]);
create('case-alias', [...core('2.0.0'), { name: 'INSTALL.sh' }]);
create('normalization-alias', [...core('2.0.0'), { name: 'é.txt' }, { name: 'é.txt' }]);
create('local-name', [...core('2.0.0'), { name: 'README.md', localName: 'OTHER.md' }]);
create('local-double-slash', core('2.0.0').map(entry => entry.name === 'install.sh' ? { ...entry, localName: '/install.sh' } : entry));
create('missing-high', core('99.0.0').filter(entry => entry.name !== 'install.sh'));
create('crc-high', [...core('98.0.0'), { name: 'README.md', badCRC: true }]);
create('version-32', core(`${'9'.repeat(27)}.0.0`));
create('version-33', core(`${'9'.repeat(28)}.0.0`));
create('size-over', [...core('97.0.0'), { name: 'README.md', data: Buffer.alloc(64 * 1024 * 1024) }]);
create('controls', [...core('2.0.0'), { name: 'CHANGELOG.md', data: '## 2.0.0\n안내\u001b[31m\u0007본문\u007f\n' }]);
for (const host of [0, 3, 10]) create(`symlink-host-${host}`, [...core('2.0.0'), { name: 'link', data: 'VERSION', host, mode: 0o120777 }]);
create('symlink-write', [...core('2.0.0'),
  { name: 'link', data: '../../escaped', host: 0, mode: 0o120777 },
  { name: 'link/payload', data: '덮어쓰면 안 됨\n' },
]);
