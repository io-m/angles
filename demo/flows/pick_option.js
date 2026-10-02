// Picks the follow-up chip whose words overlap FOLLOWUP_REPLY the most.
// -1 means no chip shares a word, so the flow types FOLLOWUP_REPLY instead.
var STOP = { i: 1, a: 1, an: 1, the: 1, to: 1, of: 1, and: 1, or: 1, it: 1, is: 1, my: 1, me: 1, yet: 1, that: 1 };

function words(text) {
  return String(text || '')
    .toLowerCase()
    .replace(/[\u2019']/g, '')
    .split(/[^a-z0-9]+/)
    .filter(function (w) { return w.length > 1 && !STOP[w]; });
}

var reply = words(FOLLOWUP_REPLY);
var best = -1;
var bestScore = 0;
var options = output.demo.options || [];
for (var i = 0; i < options.length; i++) {
  var optionWords = words(options[i]);
  var score = 0;
  for (var j = 0; j < optionWords.length; j++) {
    if (reply.indexOf(optionWords[j]) >= 0) {
      score += 1;
    }
  }
  if (score > bestScore) {
    bestScore = score;
    best = i;
  }
}
output.demo.optionIndex = best;
