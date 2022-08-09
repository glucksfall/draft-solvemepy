set -e

cd src/fva
echo 'Compiling qvaryME...'
f2py -m qvaryME -h qvaryME.pyf qvaryME.f90 --overwrite-signature 1> /dev/null 2> /dev/null
f2py -c qvaryME.pyf qvaryME.f90 -L/opt/developing/solvemepy.glucksfall/ -lquadminos 1> /dev/null 2> /dev/null
cd -

cd src/lp
echo 'Compiling warmLP...'
f2py -m warmLP -h warmLP.pyf warmLP.f90 --overwrite-signature 1> /dev/null 2> /dev/null
f2py -c warmLP.pyf warmLP.f90 -L/opt/developing/solvemepy.glucksfall/ -lminos 1> /dev/null 2> /dev/null
echo 'Compiling qwarmLP...'
f2py -m qwarmLP -h qwarmLP.pyf qwarmLP.f90 --overwrite-signature 1> /dev/null 2> /dev/null
f2py -c qwarmLP.pyf qwarmLP.f90 -L/opt/developing/solvemepy.glucksfall/ -lquadminos 1> /dev/null 2> /dev/null
cd -

cd src/nlp
echo 'Compiling qsolveME...' # qMEfuns.f90??
f2py -m qsolveME -h qsolveME.pyf qmatrixA.f90 --overwrite-signature 1> /dev/null 2> /dev/null
f2py -c qsolveME.pyf qmatrixA.f90 -L/opt/developing/solvemepy.glucksfall/ -lquadminos 1> /dev/null 2> /dev/null
echo 'Compiling qmatrixA...'
f2py -m qmatrixA -h qmatrixA.pyf qmatrixA.f90 --overwrite-signature 1> /dev/null 2> /dev/null
f2py -c qmatrixA.pyf qmatrixA.f90 -L/opt/developing/solvemepy.glucksfall/ -lquadminos 1> /dev/null 2> /dev/null
cd -

ln -sf src/fva/*.so .
ln -sf src/lp/*.so .
ln -sf src/nlp/*.so .

# Extension(name="qminospy.qvaryME", sources=["qminospy/src/fva/qvaryME.f90"], **compile_args_quad),
# Extension(name="qminospy.warmLP", sources=["qminospy/src/lp/warmLP.f90"], **compile_args_double),
# Extension(name="qminospy.qwarmLP", sources=["qminospy/src/lp/qwarmLP.f90"], **compile_args_quad),
# Extension(name="qminospy.qsolveME", sources=["qminospy/src/nlp/qsolveME.f90", "qminospy/src/nlp/qmatrixA.f90"], **compile_args_quad),
