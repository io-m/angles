// The compose card's accessibility label is "<thought>. <Style> answer. <answer>".
// Stores the answer under STYLE_KEY ("auto" detects which style is showing).
var NAMES = { stoic: 'Stoic', hopeful: 'Hopeful', witty: 'Witty', tough: 'Tough', tender: 'Tender', values: 'Values' };
var label = String(maestro.copiedText || '');
var key = STYLE_KEY;
if (key === 'auto') {
  key = null;
  var bestAt = -1;
  for (var style in NAMES) {
    var found = label.lastIndexOf('. ' + NAMES[style] + ' answer. ');
    if (found > bestAt) {
      bestAt = found;
      key = style;
    }
  }
  output.demo.firstStyle = key;
}
if (key) {
  var marker = '. ' + NAMES[key] + ' answer. ';
  var at = label.lastIndexOf(marker);
  output.demo.answers[key] = at >= 0 ? label.slice(at + marker.length) : label;
  if (at >= 0 && !output.demo.thought) {
    output.demo.thought = label.slice(0, at);
  }
}
