// Picks the answer to hold on. BEST_STYLE forces a style; "auto" scores the four
// answers for the strongest concrete line: everyday objects, times, numbers, and
// a direct next step count up; stock comfort phrases, abstractions, questions,
// and length count down. Repeating the thought's own words earns little.
var STYLES = ['stoic', 'hopeful', 'witty', 'tough'];
var CONCRETE = [
  'inbox', 'email', 'résumé', 'resume', 'cover letter', 'application', 'role', 'interview',
  'phone', 'call', 'desk', 'chair', 'calendar', 'laptop', 'tab', 'screen', 'notification',
  'today', 'tonight', 'tomorrow', 'this week', 'monday', 'morning', 'hour', 'minute',
  'one ', 'two ', 'three ', 'coffee', 'kitchen', 'door', 'list', 'spreadsheet', 'linkedin',
];
var NEXT_STEP = ['pick ', 'send ', 'write ', 'apply', 'open ', 'close ', 'call ', 'set ', 'book ', 'start '];
var STOCK = [
  'journey', "you've got this", 'you got this', 'everything happens', 'silver lining',
  'embrace', 'chapter', 'universe', 'self-care', 'be kind to yourself', "it's okay to",
  'remember that', 'growth', 'in time', 'hang in there', 'brighter', 'believe in yourself',
  'stepping stone', 'blessing in disguise', 'one day at a time', 'still in the game',
  'right yes', 'is still coming', 'the rest is noise',
];
var ABSTRACT = ['verdict', 'noise', 'story', 'outcome', 'energy', 'mindset', 'potential', 'destiny'];

function count(text, list) {
  var n = 0;
  for (var i = 0; i < list.length; i++) {
    if (text.indexOf(list[i]) >= 0) {
      n += 1;
    }
  }
  return n;
}

function score(answer) {
  var text = ' ' + String(answer || '').toLowerCase() + ' ';
  if (text.trim().length === 0) {
    return -100;
  }
  var words = text.trim().split(/\s+/);
  var digits = text.match(/\d+/g);
  var s = 0;
  s += 1.5 * count(text, CONCRETE);
  s += 1.5 * Math.min(count(text, NEXT_STEP), 2);
  s += digits ? 1 * digits.length : 0;
  s -= 2 * count(text, STOCK);
  s -= 0.75 * count(text, ABSTRACT);
  if (text.indexOf('?') >= 0) {
    s -= 1;
  }
  if (words.length > 40) {
    s -= 0.2 * (words.length - 40);
  }
  if (words.length < 10) {
    s -= 1;
  }
  return Math.round(s * 100) / 100;
}

var answers = output.demo.answers || {};
var scores = {};
var best = null;
for (var k = 0; k < STYLES.length; k++) {
  var style = STYLES[k];
  if (answers[style] === undefined) {
    continue;
  }
  scores[style] = score(answers[style]);
  if (best === null || scores[style] > scores[best]) {
    best = style;
  }
}

var forced = String(typeof BEST_STYLE === 'undefined' ? 'auto' : BEST_STYLE).toLowerCase();
if (forced !== 'auto' && answers[forced] !== undefined) {
  best = forced;
}
output.demo.scores = scores;
output.demo.best = best || 'tough';
output.demo.bestForced = forced !== 'auto';
