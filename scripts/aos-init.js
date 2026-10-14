document.addEventListener('DOMContentLoaded', function(){
  if (window.AOS) {
    AOS.init({
      once: true,
      duration: 700,
      easing: 'ease-out-cubic',
      offset: 120
    });
  }
});
