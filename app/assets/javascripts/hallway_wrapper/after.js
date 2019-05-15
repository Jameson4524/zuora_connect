window.define = previousDefine;

// This'll be our "error service" for hallway
if (isHallway()) {
  $( document ).ajaxError(function( event, jqxhr, settings, thrownError ) {
    if ( jqxhr.status === 401) {
      window.location.href = '/apps/newlogin.do?retURL=' + window.location.pathname;
    }
  });
}

function isHallway() {
  var regex = new RegExp("^/services/");
  return window.location.pathname.match(regex);
}