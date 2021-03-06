#!/bin/bash
mkdir -p tex
mkdir -p pdf
cd tex
rm -R *
cd ../pdf
rm -R *
cd ..
for file in ../Opardum/*.lhs; do lhs2TeX $file --tt | sed "s/char'06/char'30/g" | sed 's/\\char126 >/$\\leadsto$/g' >> $file.tex; done
for file in ../Opardum/Storage/*.lhs; do lhs2TeX $file --tt | sed "s/char'06/char'30/g" | sed 's/\\char126 >/$\\leadsto$/g' >> $file.tex; done
for file in ../mongodb/Opardum/Storage/*.lhs; do lhs2TeX $file --tt | sed "s/char'06/char'30/g" | sed 's/\\char126 >/$\\leadsto$/g' >> $file.tex; done
for file in ../*.lhs; do lhs2TeX $file --tt | sed "s/char'06/char'30/g" | sed 's/\\char126 >/$\\leadsto$/g' >> $file.tex; done
mv ../Opardum/*.tex ./tex
mv ../Opardum/Storage/*.tex ./tex
mv ../mongodb/Opardum/Storage/*.tex ./tex
mv ../*.tex ./tex
for file in tex/*.tex; do pdflatex $file; done
mv *.pdf pdf
rm *.aux
rm *.log
