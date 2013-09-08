function install_pyload(){
   apt-get install python-crypto python-pycurl python-imaging python-beaker tesseract-ocr tesseract-ocr-eng gocr rar zip unzip unrar-nonfree rhino python-openssl python-django
   apt-get install 
   wget http://download.pyload.org/pyload-cli-v0.4.9-all.deb
   dpkg -i pyload-cli-v0.4.9-all.deb
}


