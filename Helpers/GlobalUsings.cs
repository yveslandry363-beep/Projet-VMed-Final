// Fichier : Helpers/GlobalUsings.cs (Version Corrigée)

// --- USING GLOBAUX EXPLICITES ---
global using System;
global using System.Collections.Generic;
global using System.Diagnostics;
global using System.IO;
global using System.Linq;
global using System.Net.Http;
global using System.Net.Sockets;
global using System.Text;
global using System.Threading;
global using System.Threading.Tasks;

// --- Microsoft / Extensions ---
global using Microsoft.AspNetCore.Builder;
global using Microsoft.Extensions.Configuration;
global using Microsoft.Extensions.DependencyInjection;
global using Microsoft.Extensions.Diagnostics.HealthChecks;
global using Microsoft.Extensions.Hosting;
global using Microsoft.Extensions.Logging;
global using Microsoft.Extensions.Options;
global using Microsoft.FeatureManagement;

// --- Bibliothèques Externes ---
global using Confluent.Kafka;
global using FluentValidation;
global using Google.Apis.Auth.OAuth2; // <-- Espace de noms principal de Google
global using Google.Apis.Auth.OAuth2.Flows;
global using Npgsql;
global using Polly;
global using Serilog;

// --- OpenTelemetry ---
global using OpenTelemetry.Metrics;
global using OpenTelemetry.Resources;
global using OpenTelemetry.Trace;
global using OpenTelemetry.Instrumentation.Http;
global using OpenTelemetry.Instrumentation.AspNetCore;
global using OpenTelemetry.Exporter; 

// --- Types Locaux ---
global using PrototypeGemini.Connectors;
global using PrototypeGemini.Helpers;
global using PrototypeGemini.Interfaces;
global using PrototypeGemini.Models;
global using PrototypeGemini.Serialization;
global using PrototypeGemini.Services;
global using PrototypeGemini.Settings;
global using PrototypeGemini.Validation;

// L'ancien alias erroné ('Google.Apis.Auth.OAuth2.ServiceAccount') a été supprimé.