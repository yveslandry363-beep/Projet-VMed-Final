global using Microsoft.Extensions.Hosting;
global using Microsoft.Extensions.DependencyInjection;
global using Microsoft.Extensions.Configuration;
global using Microsoft.Extensions.Logging;
global using Microsoft.Extensions.Options;
global using System;
global using System.Collections.Generic;
global using System.Diagnostics;
global using System.Linq;
global using System.Net.Http;
global using System.Text;
global using System.Text.Json;
global using System.Threading;
global using System.Threading.Tasks;
global using Serilog;

// --- AJOUTS DE LA REFONTE ---
global using Confluent.Kafka;
global using FluentValidation;
global using Google.Apis.Auth.OAuth2;
global using Microsoft.FeatureManagement;
global using Polly.Registry;
global using Polly;
global using System.Data;
global using System.Net.Sockets;
global using PrototypeGemini.Connectors;
global using PrototypeGemini.Helpers;
global using PrototypeGemini.Interfaces;
global using PrototypeGemini.Models;
global using PrototypeGemini.Serialization;
global using PrototypeGemini.Services;
global using PrototypeGemini.Settings;
global using PrototypeGemini.Validation;
// AutoBackup test 2025-11-06T19:10:13.4895794+01:00

// AutoBackup verify 2025-11-06T19:22:38.6794774+01:00
// AutoBackup verify 2025-11-06T20:16:00.0083751+01:00
// autobackup touch 2025-11-06T22:29:57.7190239+01:00
// Test trigger
