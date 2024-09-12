// test if entities module is working

const entities = require("entities");

// Function to capitalize the first letter of a string
const myTestString = "test string &amp; test string &lt; test string &gt; test string &quot; test string &apos; test string &nbsp; test string &copy; test string &reg; test string &trade; test string &cent; test string &pound; test string &yen; test string &euro; test string &sect; test string &mdash; test string &ndash; test string &rsquo; test string &lsquo; test string &ldquo; test string &rdquo; test string &laquo; test string &raquo; test string &hellip; test string &permil; test string &micro; test string &middot; test string &bull; test string";

console.log(entities.decodeHTML(myTestString));


