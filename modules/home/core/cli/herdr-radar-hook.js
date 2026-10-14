'use strict';

// Pi titles read `<pi> - [session - ]folder`.
const PI_PREFIX = '\u03c0 - ';
const SEPARATOR = ' - ';

function title(text) {
  if (!text.startsWith(PI_PREFIX)) return text;
  const rest = text.slice(PI_PREFIX.length);
  const cut = rest.lastIndexOf(SEPARATOR);
  return cut > 0 ? rest.slice(0, cut) : rest;
}

module.exports = { title };
