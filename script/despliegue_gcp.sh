#!/bin/bash

# 📌 Verificación de variables de entorno
if [[ -z "$INSTANCE" || -z "$FIREWALL" || -z "$ZONE" ]]; then
    echo "❌ ERROR: Variables de entorno no definidas."
    echo "ℹ️  Debes asignarlas antes de ejecutar este script:"
    echo '   export INSTANCE="tu-instancia"'
    echo '   export FIREWALL="tu-firewall"'
    echo '   export ZONE="tu-zona"'
    exit 1
fi

export REGION="${ZONE%-*}"  # Extrae la región de la zona

echo "🚀 Iniciando la implementación en Google Cloud..."

# 1️⃣ Crear una instancia de VM
gcloud compute instances create $INSTANCE --zone=$ZONE --machine-type=e2-micro
echo "✅ Instancia '$INSTANCE' creada en la zona '$ZONE'."

# 2️⃣ Crear el script de inicio para configurar Nginx
cat << EOF > startup.sh
#! /bin/bash
apt-get update
apt-get install -y nginx
service nginx start
sed -i -- 's/nginx/Google Cloud Platform - '"\$HOSTNAME"'/' /var/www/html/index.nginx-debian.html
EOF
echo "✅ Script de inicio creado."

# 3️⃣ Crear plantilla de instancia
gcloud compute instance-templates create web-server-template \
    --metadata-from-file startup-script=startup.sh \
    --machine-type e2-medium \
    --region $REGION
echo "✅ Plantilla de instancia creada."

# 4️⃣ Crear un grupo administrado de instancias
gcloud compute instance-groups managed create web-server-group \
    --base-instance-name web-server \
    --size 2 \
    --template web-server-template \
    --region $REGION
echo "✅ Grupo administrado de instancias creado."

# 5️⃣ Crear regla de firewall para tráfico HTTP
gcloud compute firewall-rules create $FIREWALL --allow tcp:80 --network default
echo "✅ Regla de firewall '$FIREWALL' creada."

# 6️⃣ Crear un health check HTTP para monitorear el estado de las instancias en el balanceador
gcloud compute http-health-checks create http-basic-check
echo "✅ Health check configurado para monitorear el estado de las instancias."

# 7️⃣ Asignar el puerto HTTP (80) al grupo de instancias
gcloud compute instance-groups managed set-named-ports web-server-group \
    --named-ports http:80 --region $REGION
echo "✅ Puerto HTTP asignado al grupo de instancias."

# 8️⃣ Crear el servicio de backend para el balanceador de carga
gcloud compute backend-services create web-server-backend \
    --protocol HTTP \
    --http-health-checks http-basic-check \
    --global
echo "✅ Servicio de backend creado."

# 9️⃣ Agregar el grupo de instancias al backend
gcloud compute backend-services add-backend web-server-backend \
    --instance-group web-server-group \
    --instance-group-region $REGION \
    --global
echo "✅ Grupo de instancias agregado al backend."

# 🔟 Crear un mapa de URL
gcloud compute url-maps create web-server-map --default-service web-server-backend
echo "✅ Mapa de URL creado."

# 1️⃣1️⃣ Crear el proxy HTTP
gcloud compute target-http-proxies create http-lb-proxy --url-map web-server-map
echo "✅ Proxy HTTP creado."

# 1️⃣2️⃣ Crear una regla de reenvío para recibir tráfico en el puerto 80
gcloud compute forwarding-rules create http-content-rule \
    --global \
    --target-http-proxy http-lb-proxy \
    --ports 80
echo "✅ Regla de reenvío creada."

# 📌 Listar reglas de reenvío para verificar
gcloud compute forwarding-rules list

echo "⌛ El proceso puede tardar unos minutos en completarse, ya que las instancias deben pasar de 'UNHEALTHY' a 'HEALTHY'."
echo "🔄 Puedes verificar el estado de las instancias con el siguiente comando:"
echo "   gcloud compute backend-services get-health web-server-backend --global"

