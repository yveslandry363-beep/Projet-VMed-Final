# Étape 1: Build
FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /source

# Copier les fichiers projet et restaurer les dépendances
COPY *.csproj .
RUN dotnet restore

# Copier tout le reste et construire l'application
COPY . .
RUN dotnet publish -c Release -o /app/publish

# Étape 2: Runtime
FROM mcr.microsoft.com/dotnet/aspnet:9.0
WORKDIR /app
COPY --from=build /app/publish .

# Copier les certificats Kafka dans l'image
COPY kafka_certs/ ./kafka_certs/

# Exposer le port pour les health checks
EXPOSE 8080

# Point d'entrée de l'application
ENTRYPOINT ["dotnet", "PrototypeGemini.dll"]