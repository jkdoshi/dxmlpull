REM Build Script
REM To test the program, run "testme.exe" from %OUTDIR%
set OPTS=-allobj -clean -full -unittest -debug -g -explicit
set OUTDIR=out
set IMPDIR=out\imports
set LIB=%OUTDIR%\dxmlpull.lib

rebuild src\mxparser.d src\xmlpull.d -of%LIB% -lib %OPTS% -Hd%IMPDIR%

rebuild test\testme.d %LIB% -of%OUTDIR%\testme %OPTS% -I%IMPDIR%

copy test\testme.xml %OUTDIR%
