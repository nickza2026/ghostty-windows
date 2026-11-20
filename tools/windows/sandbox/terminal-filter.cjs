'use strict';
const { Transform } = require('node:stream');

// The guest has no shared clipboard, but OSC 52 over SSH is another route to
// the host terminal clipboard. Strip it, clickable host links and file-bearing
// image/passthrough channels (e.g. Kitty t=f/t=t) while
// retaining ordinary TUI text/control sequences. This is not a terminal-CVE sandbox.
class TerminalFilter extends Transform {
  constructor() { super(); this.mode = 'text'; this.header = []; this.escape = false; this.drop = false; this.utf8 = []; this.remaining = 0; }
  _transform(chunk, encoding, callback) {
    const out = [];
    for (const byte of chunk) {
      // Validate complete UTF-8 scalars before interpreting any continuation
      // byte as a bare C1 control. At most four bytes are retained across writes.
      if (this.remaining) {
        const lead = this.utf8[0];
        const first = this.utf8.length === 1;
        const valid = byte >= 0x80 && byte <= 0xbf && !(first && (
          (lead === 0xe0 && byte < 0xa0) || (lead === 0xed && byte > 0x9f) ||
          (lead === 0xf0 && byte < 0x90) || (lead === 0xf4 && byte > 0x8f)));
        if (valid) {
          this.utf8.push(byte);
          if (--this.remaining === 0) {
            const bytes = this.utf8; this.utf8 = [];
            this._token(lead === 0xc2 ? byte : 0x100, bytes, out);
          }
          continue;
        }
        // Discard the invalid prefix, then process this byte independently.
        this.utf8 = []; this.remaining = 0;
      }
      if (byte >= 0xc2 && byte <= 0xf4) {
        this.utf8 = [byte]; this.remaining = byte < 0xe0 ? 1 : byte < 0xf0 ? 2 : 3;
      } else if (byte < 0xa0) this._token(byte, [byte], out);
      // Invalid standalone continuation/lead bytes are never reflected.
    }
    if (out.length) this.push(Buffer.from(out)); callback();
  }
  _token(byte, bytes, out) {
      if (byte >= 0x80 && byte <= 0x9f) {
        if (byte === 0x9c) { // ST terminates both OSC and private strings.
          if (this.mode === 'osc' && !this.drop) out.push(0x1b, 0x5c);
          this.mode = 'text'; this.header = []; this.escape = false; this.drop = false;
          return;
        }
        if (this.mode === 'private' || (this.mode === 'osc' && this.drop)) return;
        if (byte === 0x9d || [0x90, 0x98, 0x9e, 0x9f].includes(byte)) {
          // Also contain nested C1 string openers in allowed OSC payloads.
          if (this.mode === 'osc' && !this.drop) out.push(0x1b, 0x5c);
          this.mode = byte === 0x9d ? 'header' : 'private';
          this.header = byte === 0x9d ? [0x1b, 0x5d] : [];
          this.escape = false; this.drop = false;
        } else if (byte === 0x9b && this.mode === 'text') {
          if (this.escape) out.push(0x1b);
          this.escape = false; out.push(0x1b, 0x5b);
        }
        return;
      }
      if (this.mode === 'text') {
        if (this.escape) {
          this.escape = false;
          if (byte === 0x5d) { this.mode = 'header'; this.header = [0x1b, 0x5d]; return; }
          if ([0x50, 0x5f, 0x5e, 0x58].includes(byte)) { this.mode = 'private'; return; }
          out.push(0x1b);
        }
        if (byte === 0x1b) this.escape = true; else out.push(...bytes);
        return;
      }
      if (this.mode === 'header') {
        this.header.push(byte);
        if (byte === 0x3b) {
          const command = Buffer.from(this.header.slice(2, -1)).toString('ascii');
          this.drop = /^\d+$/.test(command) && [7, 8, 9, 52, 1337].includes(Number(command));
          if (!this.drop) out.push(...this.header);
          this.header = []; this.mode = 'osc'; this.escape = false;
        } else if (byte === 7 || this.header.length > 24 || (byte < 0x30 || byte > 0x39)) {
          // Unknown/malformed OSC is discarded rather than reflecting a partial
          // potentially-sensitive command into the host parser.
          if (byte === 7) this.mode = 'text'; else { this.mode = 'osc'; this.drop = true; this.escape = byte === 0x1b; }
          this.header = [];
        }
        return;
      }
      if (this.mode === 'private') {
        if ((this.escape && byte === 0x5c) || byte === 0x9c) { this.mode = 'text'; this.escape = false; }
        else this.escape = byte === 0x1b;
        return;
      }
      if (!this.drop && this.escape) {
        // Never forward a nested ESC opener inside an allowed OSC. End the
        // outer string explicitly, then apply the ordinary control policy.
        out.push(0x1b, 0x5c); this.mode = 'text'; this.escape = false;
        if (byte !== 0x5c) { this.escape = true; this._token(byte, bytes, out); }
        return;
      }
      if (!this.drop && byte === 0x1b) { this.escape = true; return; }
      if (!this.drop) out.push(...bytes);
      if (byte === 7 || (this.escape && byte === 0x5c)) { this.mode = 'text'; this.escape = false; this.drop = false; }
      else this.escape = byte === 0x1b;
  }
  _flush(callback) {
    // Never emit an unterminated buffered OSC header at stream completion.
    if (this.mode === 'text' && this.escape) this.push(Buffer.from([0x1b]));
    callback();
  }
}
module.exports = { TerminalFilter };
