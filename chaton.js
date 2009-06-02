//
// NB: This script is read in both the main html and inner frame html
//

//=================================================================
// Functions for outer html
//

// Post interface ----------------------------------

function post() {
  setNickCookie($F('post-remember'));
  if ($F('post-nick') == '' || $F('post-text') == '') return;
  disablePost();
  new Ajax.Request("@@httpd-url@@@@url-path@@@@cgi-script@@",
    {
      parameters : {
        nick: $F('post-nick'), 
	text: $F('post-text')
      },
      onSuccess : function (t) { enablePost(true); },
      onFailure : function (t) { enablePost(false); },
      onException : function (r, e) { enablePost(false); }
    });
}

function textKey(e) {
  if ($('post-text').disabled) return;
  var key = (e.which || e.keyCode);
  if (key == Event.KEY_RETURN) { post(); }
}

function disablePost() {
  $('post-submit').disabled = true;
  $('post-nick').disabled = true;
  $('post-text').disabled = true;
  $('post-form').disabled = true;
}

function enablePost(clearp) {
  $('post-submit').disabled = false;
  $('post-nick').disabled = false;
  $('post-text').disabled = false;
  $('post-form').disabled = false;
  if (clearp) { $('post-text').clear(); }
  $('post-submit').focus();
  $('post-text').focus();
}

function setNickname() {
    var cookies = document.cookie.split(';');
    var len = cookies.length;
    for (var i = 0; i < len; i++) {
        var sc = cookies[i].strip();
        if (sc.startsWith('chaton-nickname=')) {
            var nick = sc.substring('chaton-nickname='.length, sc.length);
            $('post-nick').value = unescape(nick);
            $('post-remember').checked = true;
            break;
        }
    }
}

function setNickCookie(set) {
    if (set) {
        document.cookie = 'chaton-nickname=' + escape($F('post-nick'))
            + ';expires=Tue, 19 Jan 2038 00:00:00 GMT'
            + ';path=@@cookie-path@@';
    } else {
        document.cookie = 'chaton-nickname='
            + ';expires=Thu, 01-Jan-1970 00:00:01 GMT'
            + ';path=@@cookie-path@@';
    }
}
   
// Sequence count monitor -----------------------------

var messageMonitorRunning = false;
var messageMonitorContinue = false;
var currentMessageNum = -1;
var viewedMessageNum = -1;

function setTitle() {
  if (messageMonitorContinue) {
    var num = currentMessageNum - viewedMessageNum;
    if (num > 0) {
      window.document.title = '[' + num + '] Chaton @@room-name@@';
      return;
    }
  }
  window.document.title = 'Chaton @@room-name@@';
}

function messageMonitorRun() {
  messageMonitorContinue = true;
  if (!messageMonitorRunning) {
    messageMonitorRunning = true;
    currentMessageNum = viewedMessageNum = -1;
    fetchMessageCount();
  }
}

function messageMonitorStop() {
  messageMonitorContinue = false;
  currentMessageNum = viewedMessageNum = -1;
  setTitle();
}

function fetchMessageCount() {
  if (!messageMonitorContinue) {
    messageMonitorRunning = false;
    return;
  }
  new Ajax.Request("@@httpd-url@@@@url-path@@var/seq",
    {
      method: 'get',
      evalJSON: false,
      onSuccess: fetchMessageCountCB,
      onFailure: function (r,e) { messageMonitorStop(); }
    });
}

function fetchMessageCountCB(t) {
  if (!messageMonitorContinue) {
    messageMonitorRunning = false;
    return;
  }
  var cnt = parseInt(t.responseText);
  if (currentMessageNum < 0 || currentMessageNum > cnt) {
    currentMessageNum = viewedMessageNum = cnt;
  } else {
    currentMessageNum = cnt;
  }
  setTitle();
  setTimeout(fetchMessageCount, 15000);
}

// Initialization -------------------------------------
function initMainBody() {
  $('post-text').observe('keypress', textKey);
  $('the-body').onmouseover = function () { messageMonitorStop(); }
  $('the-body').onmouseout  = function () { messageMonitorRun(); }
  setNickname();
}

//=================================================================
// Functions for inner html
//

var pos = 0;
var seq = 0;
var need_scroll = false;

function fetchContent(cid) {
    seq = (seq+1)%100;
    var ts = ((new Date).getTime()).toString(36) + seq.toString(36);
    new Ajax.Request('/?t=' + ts + '&p=' + pos + '&c=' + cid,
      {
          method: 'get',
          evalJSON: 'force',
          // When Comet server disconnects, Firefox calls onSuccess with
          // emtpy content, while IE7 calls onFailure.
          onSuccess: function(t) {
              var json = t.responseJSON;
              if (!(json && json.ver && typeof(json.cid) == 'number')) {
                  fetchRetry(cid);
              } else {
                  insertContent(json, cid);
              }
          },
          onFailure: function(t) {
              fetchRetry(cid);
          }
      });
    startWatchDog(cid);
}

function fetchRetry(cid) {
    tameWatchDog();
    showStatus('Connection Lost.  Retrying...', 'status-alert');
    setTimeout(function () { resumeFetch(cid); }, 5000 + irandom(10000));
}

function insertContent(json, cid) {
    tameWatchDog();
    if (json.ver != '@@version@@') {
        // The comet server is updated.  We replace the entire document.
        document.location.href = '@@httpd-url@@:@@comet-port@@/';
        return;
    }
    if (json.cid < 0) {
        showStatus('Session Expired.  Please Reload.', 'status-alert');
        return;
    }
    showStatus('Connected ('+json.nc+' user'+(json.nc>1?'s':'')+' chatting)',
               'status-ok');
    need_scroll = true;
    if (json.pos < pos || json.refresh) {
        $('view-pane').update('');
    } else if (!isViewingBottom()) {
        need_scroll = false;
    }
    $('view-pane').insert(json.content);
    var pos_changed = (pos != json.pos);
    pos = json.pos;
    if (need_scroll) scrollToBottom();
    setTimeout(function () { fetchContent(json.cid); },
               pos_changed?irandom(1000):irandom(3000));
}

function resumeFetch(cid) {
    showStatus('Connecting...', 'status-ok');
    fetchContent(cid);
}

function showStatus(text, klass) {
    var st = $('status-line');
    st.removeChild(st.childNodes.item(0));
    st.insert('<span class=\"'+klass+'\">'+text+'</span>');
}

function checkImageSize(img) {
    var img = $(img);
    if (img.width > img.height) {
        if (img.width > @@img-size-limit@@) img.addClassName('wshrunk');
    } else {
        if (img.height > @@img-size-limit@@) img.addClassName('hshrunk');
    }
    img.style.display = 'inline';
    img.removeClassName('hide-while-loading');
    if (need_scroll) scrollToBottom();
}

function scrollToBottom() {
    var sp = $('status-pane');
    if (sp) sp.scrollTo();
}

// Hint from toru@torus.jp
function isViewingBottom() {
    var d = document;
    var de = d.documentElement;
    var w = window;
    var winh = (w.innerHeight
                || d.body.clientHeight       // IE quirk
                || (de && de.clientHeight)   // IE strict
                || 0);
    var winy = (typeof(w.pageYOffset) == 'number'
                ? w.pageYOffset
                : (typeof(d.body.scrollTop) == 'number'
                   ? d.body.scrollTop // IE quirk
                   : ((de && typeof(de.scrollTop) == 'number')
                      ? de.clientHeight // IE strict
                      : 0)));

    if (winh == 0 && winy == 0) return true;
    return winy > getDocumentHeight() - winh - 20;
}

// http://james.padolsey.com/javascript/get-document-height-cross-browser/
function getDocumentHeight() {
    var d = document;
    return Math.max(
        Math.max(d.body.scrollHeight, d.documentElement.scrollHeight),
        Math.max(d.body.offsetHeight, d.documentElement.offsetHeight),
        Math.max(d.body.clientHeight, d.documentElement.clientHeight)
    );
}

function irandom(n) {
    for (;;) {
        var r = Math.floor(Math.random() * n);
        if (r != n) return r;
    }
}

// Watchdog ------------------------------------------
//  Some browsers (e.g. Safari) do not call any callback
//  when server disconnects Ajax client.  As a safety net we set
//  watchdog timer for Comet connection.  In normal circumstances
//  the Comet server replies at most 6 minutes---if we don't hear
//  from the server for 8 minutes, we assume the connection is lost
//  and reload the whole document.

var dog_id = null;

function startWatchDog(cid) {
    if (dog_id) clearTimeout(dog_id);                       // just in case
    dog_id = setTimeout(function () {bark(cid);}, 8*60000); // 8 minutes
}

function bark(cid) {
    // We don't retry fetch, since there's no reliable way to cancel
    // the ongoing Ajax request.  We replace the whole document instead.
    showStatus('Connection Lost.  Retrying...', 'status-alert');
    document.location.href = '@@httpd-url@@:@@comet-port@@/';
}

function tameWatchDog() {
    if (dog_id) {
        clearTimeout(dog_id);
        dog_id = null;
    }
}

// Initialization -------------------------------------
function initViewFrame(cid) {
    setTimeout(function () { fetchContent(cid); }, 1);
}


