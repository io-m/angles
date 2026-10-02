// Splits DEMO_LINE into short phrases so the typing has a natural rhythm.
var words = String(DEMO_LINE).split(' ');
var chunks = [];
var current = '';
for (var i = 0; i < words.length; i++) {
  current = current ? current + ' ' + words[i] : words[i];
  var ends = /[,.!?]$/.test(words[i]);
  if ((ends && current.split(' ').length >= 3) || current.split(' ').length >= 5) {
    chunks.push(chunks.length === 0 ? current : ' ' + current);
    current = '';
  }
}
if (current) {
  chunks.push(chunks.length === 0 ? current : ' ' + current);
}
output.demo.chunks = chunks;
output.demo.chunkIndex = 0;
