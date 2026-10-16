/* Contents/Helpers/SWGL on Mac Rosetta Check.app: an Intel-only (x86_64) app that does
 * nothing. When Rosetta is missing, opening it makes macOS offer to install Rosetta in its own
 * dialog, which a script running Wine directly never gets (see ensure_rosetta in src/main.sh). */
int main(void) { return 0; }
