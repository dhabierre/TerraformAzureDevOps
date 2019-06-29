# Utilisation de Terraform dans Azure DevOps

## Terraform

[Terraform](https://www.terraform.io/) est un outil open-source développé par [HashiCorp](https://www.hashicorp.com/products/terraform/), utilisé pour provisionner et gérer des infrastructures IT dans le cloud. Ecrit en Go et fonctionnant en mode Infrastructure as a Code, il permet d’administrer l’infrastructure grâce à du code au lieu de procéder à un ensemble d'opérations manuelles.

La force de Terraform est de reposer sur un langage de description d'infrastructure simple et lisible : le HCL. L'approche IAC de Terraform permet de gérer le versioning d'une infrastructure en lui ajoutant ou retirant des composants.

Pour débuter avec Terraform :

- [Comment déployer votre infrastructure Azure en toute sécurité avec Terraform](https://blog.cellenza.com/cloud-2/azure/comment-deployer-votre-infrastructure-azure-en-toute-securite-avec-terraform/)
- [Provisionner votre infrastructure Azure avec Terraform](https://blog.cellenza.com/cloud-2/azure/provisionner-votre-infrastructure-azure-avec-terraform/)

## Objectif

Dans cet article, nous allons voir comment utiliser conjointement Terraform et Azure DevOps dans l'optique de déployer une infrastructure Azure, de manière automatique et continue.

Nos buts ici sont :

1. Définir une stack Terraform simple,
2. Intégrer Terraform dans un pipeline de Release continue d'Azure DevOps.

Notre exemple portera sur les ressources suivantes :

- 1 Web API
- 1 SQL Database
- 1 KeyVault

La Web API aura besoin de connaître la chaîne de connexion de la base. Afin de ne pas exposer de données sensibles, cette chaîne de connexion sera stockée dans le KeyVault lors de l'exécution de Terraform.

Les environnements que nous mettrons en place seront : DEV, REC et PRD

## Initialisation du projet

Les sources sont [disponibles ici](https://).

Première étape, connectons nous à Azure DevOps et créons un nouveau projet que nous nommons **TerraDevOps** puis clonons le pour commencer à travailler !

Voici la structure de fichier que nous allons adopter :

```
|-- src\
|-- terraform\
|-- README.md
```

- src\ contiendra les sources de la Web API,
- terraform contiendra l'ensemble des fichiers de la stack applicative.

### Applicatif

Créons une API ASP.NET Core dans le répertoire src\

![api-01](./images/api-01.png)
![api-02](./images/api-02.png)

Afin de protéger la chaîne de connexion à la base, nous allons avoir recours au service KeyVault d'Azure. Pour pouvoir y accéder, ajoutons la dépendence : **Microsoft.Extensions.Configuration.AzureKeyVault**.

![api-03](./images/api-03.png)

Ajouton un fichier **web.config** afin d'éviter l'erreur suivante lors du build dans Azure DevOps :

```
No web project was found in the repository. Web projects are identified by presence of either a web.config file or wwwroot folder in the directory.
Project file(s) matching the specified pattern were not found.
```

```xml
<?xml version="1.0" encoding="utf-8"?>
<configuration>

  <!-- To customize the asp.net core module uncomment and edit the following section. 
  For more info see https://go.microsoft.com/fwlink/?linkid=838655 -->
  <!--
  <system.webServer>
    <handlers>
      <remove name="aspNetCore"/>
      <add name="aspNetCore" path="*" verb="*" modules="AspNetCoreModule" resourceType="Unspecified"/>
    </handlers>
    <aspNetCore processPath="%LAUNCHER_PATH%" arguments="%LAUNCHER_ARGS%" stdoutLogEnabled="false" stdoutLogFile=".\logs\stdout" />
  </system.webServer>
  -->

</configuration>
```

Editons le fichier **Program.cs** :

```cs
namespace MyWebApi
{
    using Microsoft.AspNetCore;
    using Microsoft.AspNetCore.Hosting;
    using Microsoft.Extensions.Configuration;

    public class Program
    {
        public static void Main(string[] args)
        {
            CreateWebHostBuilder(args).Build().Run();
        }

        public static IWebHostBuilder CreateWebHostBuilder(string[] args) =>
            WebHost.CreateDefaultBuilder(args)
                .ConfigureAppConfiguration((context, config) =>
                {
                    var builtConfig = config.Build();

                    config.AddAzureKeyVault(
                        $"https://{builtConfig["KeyVaultName"]}.vault.azure.net/",
                        builtConfig["AzureADApplicationId"],
                        builtConfig["AzureADPassword"]);
                })
                .UseStartup<Startup>();
    }
}
```

Editons le fichier **Startup.cs** :

```cs
namespace MyWebApi
{
    using Microsoft.AspNetCore.Builder;
    using Microsoft.AspNetCore.Hosting;
    using Microsoft.AspNetCore.Mvc;
    using Microsoft.Extensions.Configuration;
    using Microsoft.Extensions.DependencyInjection;

    public class Startup
    {
        public IConfiguration Configuration { get; }

        public Startup(IConfiguration configuration)
        {
            this.Configuration = configuration;
        }

        public void ConfigureServices(IServiceCollection services)
        {
            services.AddSingleton(this.Configuration);

            services.AddMvc().SetCompatibilityVersion(CompatibilityVersion.Version_2_2);
        }

        public void Configure(IApplicationBuilder app, IHostingEnvironment env)
        {
            if (env.IsDevelopment())
            {
                app.UseDeveloperExceptionPage();
            }
            else
            {
                app.UseHsts();
            }

            app.UseHttpsRedirection();
            app.UseMvc();
        }
    }
}
```

Editons le fichier **ValuesController.cs** :

```cs
namespace MyWebApi.Controllers
{
    using System;
    using Microsoft.AspNetCore.Mvc;
    using Microsoft.Extensions.Configuration;

    [Route("api/[controller]")]
    [ApiController]
    public class ValuesController : ControllerBase
    {
        private readonly IConfiguration configuration;
        
        public ValuesController(IConfiguration configuration)
        {
            this.configuration = configuration ?? throw new ArgumentNullException(nameof(configuration));
        }

        [HttpGet]
        public ActionResult<string> Get()
        {
            return this.configuration["ConnectionString:Default"] ?? "UNDEFINED";
        }
    }
}

```

Editons le fichier **appsettings.json** :

```json
{
  "Logging": {
    "LogLevel": {
      "Default": "Warning"
    }
  },
  "AllowedHosts": "*",
  "KeyVaultName": "dev-mywebapi-keyvault",
  "AzureADApplicationId": "???",
  "AzureADPassword": "???"
}
```

- KeyVaultName : nom de la ressource KeyVault
- AzureADApplicationId : GUID de l'application donnant l'accès au KeyVault
- AzureADPassword : Password de l'application donnant l'accès au KeyVault

Voyons comment récupérer les valeurs des champs **AzureADApplicationId** & **AzureADPassword**.

Rendons bous dans **Azure Active Directory** et allons sur **App registrations**.

![azure-ad-01](./images/azure-ad-01.png)

Ajoutons une seconde key :

![azure-ad-02](./images/azure-ad-02.png)

Puis mettons à jour le fichier **appsettings.json** avec la clé générée une fois l'action  **Save** réalisée :

```json
{
  "Logging": {
    "LogLevel": {
      "Default": "Warning"
    }
  },
  "AllowedHosts": "*",
  "KeyVaultName": "dev-mywebapi-keyvault",
  "AzureADApplicationId": "bea87893-9a9e-4eef-b354-2e37a3caa8de",
  "AzureADPassword": "Osjiv41dRwtuVX9uOnuj/1ZBbNuS+sGX3qvFQX/Zcys="
}
```

N'oublions pas de pusher les modifications sur le repository.

À ce stade, l'API ne peut pas fonctionner pas car nous n'avons pas la ressource KeyVault de déployer.

### Terraform / Infrastructure

Côté Terraform, nous allons créer différents fichiers :

```
|-- src\
|-- terraform\
    |-- main.tf
    |-- outputs.tf
    |-- provider.tf
    |-- variables.tf
    |-- variables.tfvars
|-- README.md
```

#### main.tf

Ce fichier défini l'ensemble des ressources que Terraform doit gérer.

```terraform
data "azurerm_client_config" "current" {}

locals {
  resource_prefix     = "${var.environment}-${var.application}"
  resource_group_name = "${var.environment}-${var.application}"

  tags = {
    application = "${var.application}"
    environment = "${var.environment}"
    deployment  = "terraform"
  }
}

# ======================================================================================
# Resource Group
# ======================================================================================

resource "azurerm_resource_group" "app_resource_group" {
  location = "${var.location}"
  name     = "${local.resource_group_name}"
  tags     = "${local.tags}"
}

# ======================================================================================
# Service Plan
# ======================================================================================

resource "azurerm_app_service_plan" "app_service_plan" {
  name                = "${local.resource_prefix}-app-service-plan"
  location            = "${azurerm_resource_group.app_resource_group.location}"
  resource_group_name = "${azurerm_resource_group.app_resource_group.name}"

  sku {
    tier = "Free"
    size = "F1"
  }

  tags = "${local.tags}"
}

# ======================================================================================
# App Service
# ======================================================================================

resource "azurerm_app_service" "app_service" {
  name                = "${local.resource_prefix}-app-service"
  location            = "${azurerm_resource_group.app_resource_group.location}"
  resource_group_name = "${azurerm_resource_group.app_resource_group.name}"
  app_service_plan_id = "${azurerm_app_service_plan.app_service_plan.id}"
  https_only          = true

  identity {
    type = "SystemAssigned"
  }

  tags = "${local.tags}"
}

# ======================================================================================
# KeyVault
# ======================================================================================

resource "azurerm_key_vault" "key_vault" {
  name                        = "${local.resource_prefix}-keyvault"
  location                    = "${azurerm_resource_group.app_resource_group.location}"
  resource_group_name         = "${azurerm_resource_group.app_resource_group.name}"
  tenant_id                   = "${data.azurerm_client_config.current.tenant_id}"
  enabled_for_disk_encryption = true

  sku {
    name = "standard"
  }

  access_policy {
    tenant_id = "${data.azurerm_client_config.current.tenant_id}"
    object_id = "${data.azurerm_client_config.current.service_principal_object_id}"

    key_permissions = [
      "get",
      "list",
      "create",
      "delete"
    ]

    secret_permissions = [
      "get",
      "list",
      "set",
      "delete"
    ]
  }

  tags = "${local.tags}"
}

resource "azurerm_key_vault_access_policy" "key_vault_access_policy_app_service" {
  key_vault_id = "${azurerm_key_vault.key_vault.id}"
  tenant_id    = "${data.azurerm_client_config.current.tenant_id}"
  object_id    = "${azurerm_app_service.app_service.identity.0.principal_id}"

  key_permissions = [
    "get",
    "list",
    "delete"
  ]

  secret_permissions = [
    "get",
    "list",
    "delete"
  ]
}

# ======================================================================================
# Azure SQL Server & Database
# ======================================================================================

resource "azurerm_sql_server" "sql_server" {
  name                         = "${local.resource_prefix}-sqlserver"
  location                     = "${azurerm_resource_group.app_resource_group.location}"
  resource_group_name          = "${azurerm_resource_group.app_resource_group.name}"
  version                      = "12.0"
  administrator_login          = "${var.sql_server_login}"
  administrator_login_password = "${var.sql_server_password}"
  tags                         = "${local.tags}"
}

resource "azurerm_sql_database" "sql_database" {
  name                = "${local.resource_prefix}-db"
  resource_group_name = "${azurerm_resource_group.app_resource_group.name}"
  location            = "${azurerm_resource_group.app_resource_group.location}"
  server_name         = "${azurerm_sql_server.sql_server.name}"
  tags                = "${local.tags}"
}

resource "azurerm_key_vault_secret" "key_vault_secret_connectionstring" {
  name         = "ConnectionString--Default"
  value        = "Server=tcp:${azurerm_sql_server.sql_server.fully_qualified_domain_name},1433;Initial Catalog=${azurerm_sql_database.sql_database.name};Persist Security Info=False;User ID=${azurerm_sql_server.sql_server.administrator_login};Password=${azurerm_sql_server.sql_server.administrator_login_password};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
  key_vault_id = "${azurerm_key_vault.key_vault.id}"
  tags         = "${local.tags}"
}

resource "azurerm_sql_firewall_rule" "sql_firewall_rule_allow_access_to_azure_services" {
  name                = "${local.resource_prefix}-firewall-rule-allow-access-to-azure-services"
  resource_group_name = "${azurerm_resource_group.app_resource_group.name}"
  server_name         = "${azurerm_sql_server.sql_server.name}"
  start_ip_address    = "0.0.0.0"
  end_ip_address      = "0.0.0.0"
}
```

Notons la syntaxe du nom de la ressource **key_vault_secret_connectionstring** : __ConnectionString--Default__. Lors de l'exécution de la Web Api, il sera possible d'accéder à la valeur via :

```cs
var connection = this.configuration["ConnectionString:Default"];
```

Comme nous l'avons vu précédemment, l'objet _configuration_ est configuré pour récupérer des secrets dans le KeyVault.

#### outputs.tf

Ce fichier défini les outputs que retournera Terraform une fois les ressources créées.

```terraform
output "subscription_id" {
  value = "${data.azurerm_client_config.current.subscription_id}"
}

output "app_service_hostname" {
  value = "${azurerm_app_service.app_service.default_site_hostname}"
}

output "key_vault_uri" {
  value = "${azurerm_key_vault.key_vault.vault_uri}"
}
```

#### provider.tf

La section **backend** permet de stocker le fichier tfstate sur un Storage Account ([pour en savoir plus](https://www.terraform.io/docs/backends/)).

```terraform
provider "azurerm" {
  version = "1.23.0"
}

terraform {
  required_version = "0.11.13"
  backend "azurerm" {
    storage_account_name = "shared__application__tfsa"
    container_name       = "terraform"
    key                  = "terraform-__environment__.tfstate"
    access_key           = "__tf_storage_account_key__"
  }
}
```

Notons les clés suivantes :

- storage_account_name = "shared\_\_application\_\_tfsa"
- key = "terraform-\_\_environment\_\_.tfstate"
- access_key = "\_\_tf_storage_account_key\_\_"

Les différents tokens _\_\_token_name\_\__ seront remplacés automatiquement avant le déploiement de l'infrastructure.

#### variables.tf

Ce fichier défini les différentes variables utilisées.

```terraform
variable "location" {
  type = "string"
}

variable "environment" {
  type = "string"
}

variable "application" {
  type = "string"
}

variable "sql_server_login" {
  type = "string"
}

variable "sql_server_password" {
  type = "string"
}
```

#### variables.tfvars

Ce fchier défini les valeurs des variables. Dans notre cas, nous utilisons des tokens qui seront automatiquement remplacés lors du déploiement, en fonction de l'environnement cible.

```terraform
location = "__location__"
environment = "__environment__"
application = "__application__"
sql_server_login = "__sql_server_login__"
sql_server_password = "__sql_server_password__"
```

Certaines d'entres elles sont indépendantes de l'environnement (location, application) et d'autres non (environement, sql_server_*).

N'oublions pas de pusher les modifications.

### Création du pipeline Azure DevOps

Une fois la Web Api et le Terraform en place, nous pouvons mettre en place la CI/CD.

#### Build

Créons une nouvelle **Build Pipeline**.

Cliquons sur le lien **Use the visual designer** pour passer en mode visuel.

![build-01](./images/build-01.png)

Pour nous simplifier la tâche, restons sur la branche **master**.

![build-02](./images/build-02.png)

Sélectionnons une build de type **ASP.NET Core** pour compiler notre Web API.

![build-03](./images/build-03.png)

Modifions uniquement au niveau du step **Publish** la valeur du champ **Arguments** :

![build-04](./images/build-04.png)

Ajoutons un step de type **Copy files** avant **Publish Artifact**. Ce step sert à embarquer les fichiers de Terraform dans l'artifact.

![build-05](./images/build-05.png)
![build-06](./images/build-06.png)

Lançons notre première build. Si tout se passe bien, nous obtenons l'artifact suivant :

![build-07](./images/build-07.png)

On y retrouve bien :

- drop\MyWebApi\MyWebApi.zip : zip contenant les binaires de la Web Api
- drop\Terraform\* : les fichiers de la stack Terraform.

#### Release

Créons à présent une nouvelle **Release Pipeline**.

Partons du template **Empty job**.

![release-01](./images/release-01.png)

Et renommons le premier stage **DEV**.

![release-02](./images/release-02.png)

Ajoutons un artifact.

![release-03](./images/release-03.png)

Activons le **Continuos deployment trigger** pour lancer une release sur DEV dès qu'une build a été exécutée (il faudra également au niveau de la build activer l'intégration continue pour qu'une build soit exécutée dès qu'un push est effectif sur le repository).

![release-04](./images/release-04.png)

Pour utiliser Terraform, nous avons besoin de :

1. créer son backend sur Azure Storage (Blob),
2. récupérer la Key de ce Storage et l'injecter dans les variables pour pouvoir écrire/lire dans le Blob.

Première étape, ajoutons un step de type **Azure CLI** pour la création du backend :

![release-05](./images/release-05.png)

Inline script :

```ps
call az group create --location $(location) --name "shared-$(application)" --tags application="$(application)" deployment="terraform"

call az storage account create --name "shared$(application)tfsa" --resource-group "shared-$(application)" --location $(location) --sku Standard_LRS  --tags application="$(application)" deployment="terraform"

call az storage container create --name "terraform" --account-name "shared$(application)tfsa" --public-access off
```

Ce script créé :

1. un _Resoure Group_, indépendant de l'environnement déployé,
2. un _Storage Account_,
3. un _Blob_ nommé _terraform_ qui contiendra les tfstates de chaque environnement déployé.

Ajoutons ensuite un second step de type **Azure Powershell script** (en version _4.* (preview)_ pour le support de l'extension Az).

![release-06](./images/release-06.png)

Inline script :

```ps
$key = (Get-AzStorageAccountKey -ResourceGroup "shared-$(application)" -Name "shared$(application)tfsa").Value[0]

Write-Host "##vso[task.setvariable variable=tf_storage_account_key]$key"
```

Ce script récupère la Key du Storage Account et l'injecte dans la variable **tf_storage_account_key** (que nous ferons un peu plus loin).

Les 2 étapes suivantes permettent de substituer les tokens présents dans les fichiers Terraform.

![release-07](./images/release-07.png)
![release-08](./images/release-08.png)
![release-09](./images/release-09.png)

Pour chacun de ces 2 steps, n'oublions pas de changer les Token **prefix** et **suffix** dans la section **Advanced** (avec double-underscores). 

![release-10](./images/release-10.png)

Ajoutons les steps suivants qui concerne l'exécution de Terraform :

- init
- apply (en approbation automatique)

Remarque : idéalement, nous devrions ajouter le step _validate_ juste avant le step _apply_ afin de valider la stack avant exécution de celle-ci.

![release-11](./images/release-11.png)
![release-12](./images/release-12.png)
![release-13](./images/release-13.png)

Ajoutons finalement le step pour déployer la Web Api ans oublier la transformation du fichier **appsettings.json**.

![release-14](./images/release-14.png)

Une fois le stage **DEV** finalisé, faisons-en un clone que l'on nomme **REC**. Réitérons l'opération **REC** -> **PRD**.

![release-15](./images/release-15.png)

Activons aux stages **REC* et *PRD** l'option **Pre-deployment approvals** :

![release-16](./images/release-16.png)

Notre pipeline étant défini, il nous reste à définir les variables.

![release-17](./images/release-17.png)

Les valeurs des clés **KeyVaultName**, **AzureADApplicationId** et **AzureADPassword** seront injectées dans la configuration de la Web Api lors du dernier step du pipeline.

#### Exécution du pipeline

Lançons finalement notre première Release !

Une fois déployée, nous nous retrouvons avec 2 nouveaux Resource Groups :

- dev-mywebapi
- shared-mywebapi

Dans **shared-mywebapi**, nous retrouvons le Storage Account et son Blob qui contient le tfstate du déploiement de l'environnement **DEV**.

![azure-01](./images/azure-01.png)
![azure-02](./images/azure-02.png)

**dev-mywebapi** contient quant à lui les ressources applicatives.

![azure-03](./images/azure-03.png)

Reste à tester que notre Web Api fonctionne bien :

```
# GET https://dev-mywebapi-app-service.azurewebsites.net/api/values

Server=tcp:dev-mywebapi-sqlserver.database.windows.net,1433;Initial Catalog=dev-mywebapi-db;Persist Security Info=False;User ID=sqladmin;Password=!Sql@dm1nD3v;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;
```

... et à déployer les environnempents de REC et PRD :)

## Conclusion

Dans cet article, nous avons vu comment provisionner une infrastructure Azure avec Terraform, le tout, déployé de manière continue au travers d'Azure DevOps. Il est évident que tous les aspects n'ont pas été couverts, mais cela reste un point d'entrée pour notre démarche DevOps :)
