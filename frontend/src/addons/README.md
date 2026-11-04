# Community Additions add-ons: frontend parts

One folder per installed add-on (named after its id) with its page components. An add-on can also add
to CIPP's own pages through the extension points in `src/utils/addon-extensions.js`, by shipping a file
with the agreed name here (for example `userBulkEdit.js`). This file keeps the folder in place when no
add-ons are installed, because the build looks for those files here.
