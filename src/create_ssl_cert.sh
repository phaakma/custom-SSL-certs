#!/bin/sh

#https://deliciousbrains.com/ssl-certificate-authority-for-local-https-development/

# Check if running in Git Bash on Windows
if [ "$MSYSTEM" = "MINGW64" ] || [ "$MSYSTEM" = "MINGW32" ]; then
  WINDOWS_ENV=true
else
  WINDOWS_ENV=false
fi

# Number of days into the future for the expiry of the certs
DAYS=7300
# Calculate the future date in seconds since the epoch
future_date_seconds=$(( $(date +%s) + (DAYS * 86400) ))
# Format the future date as YYYYMMDD_HHMMSS
formatted_date=$(date -d "@$future_date_seconds" "+%Y%m%d_%H%M%S")

# ANSI escape codes for text colors
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
RESET="\033[0m" # Reset text color to default

echo
echo

print_usage() {
  echo "Usage: $0 -d|-domain <domain> [-o|-output <output_folder>] [-h|-help]"
  echo "  -d, -domain       Specify the domain name (required)"
  echo "  -o, -output       Specify the output folder (optional, default is 'certs' in script's directory)"
  echo "  -s, -san          Specify one or more Subject Alternative Name (SAN) DNS entries (optional)"
  echo "  -h, -help         Display this help message"
  echo ""
  echo "Examples:"
  if [ "$WINDOWS_ENV" = true ]; then
    echo "  Windows (Git Bash):"
    echo "    $0 -d example.com -o C:/path/to/output/folder"
    echo "    $0 -d example.com -o certs/output"
  else
    echo "  Linux:"
    echo "    $0 -d example.com -o /path/to/output/folder"
    echo "    $0 -d example.com -o certs/output"
  fi
  exit 1
}

validate_domain() {
  local domain="$1"

  # Check if the domain is valid
  if ! [[ "$domain" =~ ^(\*\.)?([a-zA-Z0-9-]+\.)*[a-zA-Z0-9-]+$ ]]
   then
    return 1
  fi

  # Remove all asterisks and convert dots to underscores for folder and file names
  local sanitized_domain="$(echo "$domain" | sed 's/\*/_/g;s/\./_/g')"
  # Remove underscores or dots from the start of the sanitized domain name
  sanitized_domain="$(echo "$sanitized_domain" | sed 's/^[_\.]*//')"

  # Use the sanitized name for folder and file names
  SANITIZED_FILENAME=$sanitized_domain

  return 0
}

# Check if custom.cnf exists in the same directory as the script
# Get the script's directory in Unix-style format
SCRIPT_DIR_UNIX="$(realpath "$(dirname "$0")")"

# Check if running on Windows and convert the path to Windows-style if needed
if [ "$WINDOWS_ENV" = true ]; then
  SCRIPT_DIR="$(cygpath -w "$SCRIPT_DIR_UNIX")"
else
  SCRIPT_DIR="$SCRIPT_DIR_UNIX"
fi
echo "Script directory: ${SCRIPT_DIR}"
CUSTOM_OPENSSL_CONF="$SCRIPT_DIR/custom.cnf"
DOMAIN_OPENSSL_CONF="$SCRIPT_DIR/domain.cnf"
MYCA_KEY="$SCRIPT_DIR/myCA.key"
MYCA_PEM="$SCRIPT_DIR/myCA.pem"

if [ -f "$CUSTOM_OPENSSL_CONF" ]; then
  # Set the OPENSSL_CONF environment variable to use the custom configuration file
  export OPENSSL_CONF="$CUSTOM_OPENSSL_CONF"
fi

# OpenSSL command prefix
OPENSSL_CMD="openssl"

# If running under Windows, add "winpty" prefix
if [ "$WINDOWS_ENV" = true ]; then
  OPENSSL_CMD="winpty openssl"
fi

DOMAIN=""
OUTPUT_FOLDER=""

while getopts ":d:o:s:h-:" opt; do
  case "$opt" in
    d|domain)
      DOMAIN="$OPTARG"
      # Check if the provided domain is valid (replace with your validation logic)
      if ! validate_domain "$DOMAIN"; then
        echo "Error: Invalid domain format."
        print_usage
      fi
      ;;
    o|output)
      OUTPUT_FOLDER="$OPTARG"
      ;;
    s|san)
      SAN_ENTRIES="$OPTARG"
      ;;
    h|help)
      print_usage
      ;;
    -)
      case "$OPTARG" in
        domain=*)
          DOMAIN="${OPTARG#*=}"
          # Check if the provided domain is valid (replace with your validation logic)
          if ! validate_domain "$DOMAIN"; then
            echo "Error: Invalid domain format."
            print_usage
          fi
          ;;
        output=*)
          OUTPUT_FOLDER="${OPTARG#*=}"
          ;;
        help)
          print_usage
          ;;
        *)
          echo "Unknown option: $OPTARG"
          exit 1
          ;;
      esac
      ;;
    \?)
      echo "Invalid option: -$OPTARG"
      exit 1
      ;;
  esac
done

# If no output folder specified, use the domain as the default folder name
if [ -z "$OUTPUT_FOLDER" ]
 then
  current_datetime=$(date "+%Y%m%d_%H%M%S")
  OUTPUT_FOLDER="${SANITIZED_FILENAME}_${current_datetime}"
fi

# Create the output folder if it doesn't exist
if [ ! -d "$OUTPUT_FOLDER" ]; then
  mkdir -p "$OUTPUT_FOLDER"
fi

cd "$OUTPUT_FOLDER"

if [ ! -f $MYCA_KEY ]; then
  echo 
  echo -e "${BLUE}Creating a private key.......${RESET}"
  $OPENSSL_CMD genrsa -des3 -out $MYCA_KEY 2048
fi

if [ ! -f $MYCA_PEM ]; then
  echo
  echo -e "${BLUE}Creating a Root Certificate PEM file.......${RESET}"
  $OPENSSL_CMD req -x509 -new -nodes -key $MYCA_KEY -sha256 -days 7300 -out $MYCA_PEM
fi

echo
echo -e "${GREEN}Generating a key for this domain: ${DOMAIN} ${RESET}"
$OPENSSL_CMD genrsa -out "$SANITIZED_FILENAME.key" 2048
echo
echo -e "${GREEN}Generating a CSR for this domain: ${DOMAIN} ${RESET}"
# Set the CUSTOM_CN environment variable with the desired Common Name
export CUSTOM_CN=$DOMAIN
#$OPENSSL_CMD req -new -key "$SANITIZED_FILENAME.key" -out "$SANITIZED_FILENAME.csr" -subj "//CN=$DOMAIN"
$OPENSSL_CMD req -new -key "$SANITIZED_FILENAME.key" -out "$SANITIZED_FILENAME.csr" -config $DOMAIN_OPENSSL_CONF

# Create the SAN entries dynamically based on the comma-separated list
SAN_ENTRIES_ARRAY=($(echo "$SAN_ENTRIES" | tr ',' '\n'))
SAN_ENTRIES_STRING=""

for entry in "${SAN_ENTRIES_ARRAY[@]}"; do
  SAN_ENTRIES_STRING+="DNS.$SAN_COUNTER=$entry"$'\n'
  ((SAN_COUNTER++))
done
echo
echo -e "${YELLOW}Adding Subject Alternate Names.... ${DOMAIN} and ${SAN_ENTRIES} ${RESET}"

# generating the extra SAN entries

SAN_COUNTER=2  # Initialize the counter with 2 since DNS.1 is already defined

cat > "$SANITIZED_FILENAME.ext" << EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage=digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName=@alt_names
[alt_names]
DNS.1=$DOMAIN
$SAN_ENTRIES_STRING
EOF

# Get the current date and time in the desired format (YYYYMMDD_HHMMSS)
CURRENT_DATE=$(date +"%Y%m%d_%H%M%S")

# Append the current date and time to the certificate file name (excluding private key and root cert)
CERT_FILE="$SANITIZED_FILENAME""_$formatted_date.crt"
PFX_FILE="$SANITIZED_FILENAME""_$formatted_date.pfx"

echo
echo -e "${GREEN}Exporting crt file. ${RESET}"
$OPENSSL_CMD x509 -req -in "$SANITIZED_FILENAME.csr" -CA $MYCA_PEM -CAkey $MYCA_KEY -CAcreateserial \
-out "$CERT_FILE" -days 7300 -sha256 -extfile "$SANITIZED_FILENAME.ext"

echo
echo -e "${GREEN}Exporting pfx file. You will need to specify a password ${RESET}"
# Create a PFX file for IIS with the current date and time appended to the file name
$OPENSSL_CMD pkcs12 -export -out "$PFX_FILE" -inkey "$SANITIZED_FILENAME.key" -in "$CERT_FILE" -certfile $MYCA_PEM -name $DOMAIN

echo
echo "Certificate files generated:"
echo "Private Key: $SANITIZED_FILENAME.key"
echo "Root Certificate: $MYCA_PEM"
echo "Certificate: $CERT_FILE"
echo "PFX File for IIS: $PFX_FILE"
