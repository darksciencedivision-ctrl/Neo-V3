# ============================================================
# NEO LAB v2 — DATABASE INTEGRATION MODULE
# Supports: SQL Server, SQLite, PostgreSQL
# ============================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ============================================================
# DATABASE CONFIGURATION
# ============================================================
$script:DbConfig = @{
    Provider         = "SQLite"  # SQLite | SQLServer | PostgreSQL
    ConnectionString = $null
    
    # SQLite settings
    SQLitePath       = ".\neo_lab.db"
    
    # SQL Server settings
    SQLServer        = "localhost"
    SQLDatabase      = "NeoLab"
    SQLIntegrated    = $true
    SQLUser          = ""
    SQLPassword      = ""
    
    # PostgreSQL settings
    PGHost           = "localhost"
    PGPort           = 5432
    PGDatabase       = "neolab"
    PGUser           = "neo"
    PGPassword       = ""
    
    # Connection pooling
    MaxPoolSize      = 10
    ConnectionTimeout = 30
    
    # Schema
    AutoCreateSchema = $true
}

# ============================================================
# SCHEMA DEFINITIONS
# ============================================================
$script:Schema = @{
    SQLite = @"
-- Observations table (raw input data)
CREATE TABLE IF NOT EXISTS observations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    observation_id TEXT UNIQUE NOT NULL,
    type TEXT NOT NULL,
    value REAL NOT NULL,
    metadata TEXT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    processed INTEGER DEFAULT 0
);

-- Patterns table (learned patterns)
CREATE TABLE IF NOT EXISTS patterns (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    pattern_key TEXT UNIQUE NOT NULL,
    count INTEGER DEFAULT 0,
    sum_value REAL DEFAULT 0,
    mean_value REAL DEFAULT 0,
    min_value REAL,
    max_value REAL,
    std_dev REAL DEFAULT 0,
    confidence REAL DEFAULT 0.5,
    generation INTEGER DEFAULT 1,
    first_seen DATETIME,
    last_seen DATETIME,
    metadata TEXT
);

-- Anomalies table
CREATE TABLE IF NOT EXISTS anomalies (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    pattern_key TEXT NOT NULL,
    value REAL NOT NULL,
    expected_value REAL,
    z_score REAL,
    severity TEXT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    acknowledged INTEGER DEFAULT 0,
    FOREIGN KEY (pattern_key) REFERENCES patterns(pattern_key)
);

-- Correlations table
CREATE TABLE IF NOT EXISTS correlations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    pattern_a TEXT NOT NULL,
    pattern_b TEXT NOT NULL,
    co_occurrence_count INTEGER DEFAULT 0,
    correlation_strength REAL DEFAULT 0,
    first_seen DATETIME,
    last_seen DATETIME,
    UNIQUE(pattern_a, pattern_b)
);

-- Sequences table (temporal patterns)
CREATE TABLE IF NOT EXISTS sequences (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    from_pattern TEXT NOT NULL,
    to_pattern TEXT NOT NULL,
    transition_count INTEGER DEFAULT 0,
    probability REAL DEFAULT 0,
    avg_interval_ms REAL,
    last_seen DATETIME,
    UNIQUE(from_pattern, to_pattern)
);

-- Strategies table (genetic evolution)
CREATE TABLE IF NOT EXISTS strategies (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    strategy_id TEXT UNIQUE NOT NULL,
    learning_rate REAL NOT NULL,
    memory_decay REAL NOT NULL,
    confidence_threshold REAL NOT NULL,
    prune_threshold REAL NOT NULL,
    fitness REAL DEFAULT 0,
    predictions INTEGER DEFAULT 0,
    correct_predictions INTEGER DEFAULT 0,
    generation INTEGER DEFAULT 0,
    is_active INTEGER DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME
);

-- Insights table (high-confidence learned rules)
CREATE TABLE IF NOT EXISTS insights (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    pattern_key TEXT NOT NULL,
    insight_type TEXT NOT NULL,
    description TEXT,
    confidence REAL,
    supporting_evidence TEXT,
    generation INTEGER,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    expires_at DATETIME
);

-- Metrics table (system performance)
CREATE TABLE IF NOT EXISTS metrics (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    cycle_number INTEGER,
    observations_total INTEGER,
    patterns_count INTEGER,
    avg_confidence REAL,
    anomalies_count INTEGER,
    active_strategy TEXT,
    strategy_fitness REAL,
    memory_usage_mb REAL,
    cycle_duration_ms REAL
);

-- Neural weights table (for neural network layer)
CREATE TABLE IF NOT EXISTS neural_weights (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    layer_id INTEGER NOT NULL,
    from_node INTEGER NOT NULL,
    to_node INTEGER NOT NULL,
    weight REAL NOT NULL,
    bias REAL DEFAULT 0,
    gradient REAL DEFAULT 0,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(layer_id, from_node, to_node)
);

-- Distributed nodes table
CREATE TABLE IF NOT EXISTS distributed_nodes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    node_id TEXT UNIQUE NOT NULL,
    node_name TEXT,
    endpoint_url TEXT,
    status TEXT DEFAULT 'unknown',
    last_heartbeat DATETIME,
    knowledge_version INTEGER DEFAULT 0,
    patterns_count INTEGER DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Knowledge sync log
CREATE TABLE IF NOT EXISTS sync_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source_node TEXT NOT NULL,
    target_node TEXT NOT NULL,
    sync_type TEXT NOT NULL,
    records_synced INTEGER DEFAULT 0,
    status TEXT,
    started_at DATETIME,
    completed_at DATETIME,
    error_message TEXT
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_observations_type ON observations(type);
CREATE INDEX IF NOT EXISTS idx_observations_timestamp ON observations(timestamp);
CREATE INDEX IF NOT EXISTS idx_observations_processed ON observations(processed);
CREATE INDEX IF NOT EXISTS idx_patterns_confidence ON patterns(confidence);
CREATE INDEX IF NOT EXISTS idx_anomalies_timestamp ON anomalies(timestamp);
CREATE INDEX IF NOT EXISTS idx_anomalies_severity ON anomalies(severity);
CREATE INDEX IF NOT EXISTS idx_sequences_probability ON sequences(probability);
CREATE INDEX IF NOT EXISTS idx_metrics_timestamp ON metrics(timestamp);
"@

    SQLServer = @"
-- SQL Server Schema
IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='observations' AND xtype='U')
CREATE TABLE observations (
    id BIGINT IDENTITY(1,1) PRIMARY KEY,
    observation_id NVARCHAR(50) UNIQUE NOT NULL,
    type NVARCHAR(100) NOT NULL,
    value FLOAT NOT NULL,
    metadata NVARCHAR(MAX),
    timestamp DATETIME2 DEFAULT GETUTCDATE(),
    processed BIT DEFAULT 0
);

IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='patterns' AND xtype='U')
CREATE TABLE patterns (
    id BIGINT IDENTITY(1,1) PRIMARY KEY,
    pattern_key NVARCHAR(200) UNIQUE NOT NULL,
    count INT DEFAULT 0,
    sum_value FLOAT DEFAULT 0,
    mean_value FLOAT DEFAULT 0,
    min_value FLOAT,
    max_value FLOAT,
    std_dev FLOAT DEFAULT 0,
    confidence FLOAT DEFAULT 0.5,
    generation INT DEFAULT 1,
    first_seen DATETIME2,
    last_seen DATETIME2,
    metadata NVARCHAR(MAX)
);

IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='anomalies' AND xtype='U')
CREATE TABLE anomalies (
    id BIGINT IDENTITY(1,1) PRIMARY KEY,
    pattern_key NVARCHAR(200) NOT NULL,
    value FLOAT NOT NULL,
    expected_value FLOAT,
    z_score FLOAT,
    severity NVARCHAR(20),
    timestamp DATETIME2 DEFAULT GETUTCDATE(),
    acknowledged BIT DEFAULT 0
);

IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='correlations' AND xtype='U')
CREATE TABLE correlations (
    id BIGINT IDENTITY(1,1) PRIMARY KEY,
    pattern_a NVARCHAR(200) NOT NULL,
    pattern_b NVARCHAR(200) NOT NULL,
    co_occurrence_count INT DEFAULT 0,
    correlation_strength FLOAT DEFAULT 0,
    first_seen DATETIME2,
    last_seen DATETIME2,
    CONSTRAINT UQ_correlations UNIQUE(pattern_a, pattern_b)
);

IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='sequences' AND xtype='U')
CREATE TABLE sequences (
    id BIGINT IDENTITY(1,1) PRIMARY KEY,
    from_pattern NVARCHAR(200) NOT NULL,
    to_pattern NVARCHAR(200) NOT NULL,
    transition_count INT DEFAULT 0,
    probability FLOAT DEFAULT 0,
    avg_interval_ms FLOAT,
    last_seen DATETIME2,
    CONSTRAINT UQ_sequences UNIQUE(from_pattern, to_pattern)
);

IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='strategies' AND xtype='U')
CREATE TABLE strategies (
    id BIGINT IDENTITY(1,1) PRIMARY KEY,
    strategy_id NVARCHAR(50) UNIQUE NOT NULL,
    learning_rate FLOAT NOT NULL,
    memory_decay FLOAT NOT NULL,
    confidence_threshold FLOAT NOT NULL,
    prune_threshold FLOAT NOT NULL,
    fitness FLOAT DEFAULT 0,
    predictions INT DEFAULT 0,
    correct_predictions INT DEFAULT 0,
    generation INT DEFAULT 0,
    is_active BIT DEFAULT 0,
    created_at DATETIME2 DEFAULT GETUTCDATE(),
    updated_at DATETIME2
);

IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='insights' AND xtype='U')
CREATE TABLE insights (
    id BIGINT IDENTITY(1,1) PRIMARY KEY,
    pattern_key NVARCHAR(200) NOT NULL,
    insight_type NVARCHAR(50) NOT NULL,
    description NVARCHAR(MAX),
    confidence FLOAT,
    supporting_evidence NVARCHAR(MAX),
    generation INT,
    created_at DATETIME2 DEFAULT GETUTCDATE(),
    expires_at DATETIME2
);

IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='metrics' AND xtype='U')
CREATE TABLE metrics (
    id BIGINT IDENTITY(1,1) PRIMARY KEY,
    timestamp DATETIME2 DEFAULT GETUTCDATE(),
    cycle_number INT,
    observations_total INT,
    patterns_count INT,
    avg_confidence FLOAT,
    anomalies_count INT,
    active_strategy NVARCHAR(50),
    strategy_fitness FLOAT,
    memory_usage_mb FLOAT,
    cycle_duration_ms FLOAT
);

IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='neural_weights' AND xtype='U')
CREATE TABLE neural_weights (
    id BIGINT IDENTITY(1,1) PRIMARY KEY,
    layer_id INT NOT NULL,
    from_node INT NOT NULL,
    to_node INT NOT NULL,
    weight FLOAT NOT NULL,
    bias FLOAT DEFAULT 0,
    gradient FLOAT DEFAULT 0,
    updated_at DATETIME2 DEFAULT GETUTCDATE(),
    CONSTRAINT UQ_neural_weights UNIQUE(layer_id, from_node, to_node)
);

IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='distributed_nodes' AND xtype='U')
CREATE TABLE distributed_nodes (
    id BIGINT IDENTITY(1,1) PRIMARY KEY,
    node_id NVARCHAR(50) UNIQUE NOT NULL,
    node_name NVARCHAR(100),
    endpoint_url NVARCHAR(500),
    status NVARCHAR(20) DEFAULT 'unknown',
    last_heartbeat DATETIME2,
    knowledge_version INT DEFAULT 0,
    patterns_count INT DEFAULT 0,
    created_at DATETIME2 DEFAULT GETUTCDATE()
);

IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='sync_log' AND xtype='U')
CREATE TABLE sync_log (
    id BIGINT IDENTITY(1,1) PRIMARY KEY,
    source_node NVARCHAR(50) NOT NULL,
    target_node NVARCHAR(50) NOT NULL,
    sync_type NVARCHAR(50) NOT NULL,
    records_synced INT DEFAULT 0,
    status NVARCHAR(20),
    started_at DATETIME2,
    completed_at DATETIME2,
    error_message NVARCHAR(MAX)
);

-- Create indexes
CREATE NONCLUSTERED INDEX IX_observations_type ON observations(type);
CREATE NONCLUSTERED INDEX IX_observations_timestamp ON observations(timestamp);
CREATE NONCLUSTERED INDEX IX_patterns_confidence ON patterns(confidence);
CREATE NONCLUSTERED INDEX IX_anomalies_severity ON anomalies(severity);
"@

    PostgreSQL = @"
-- PostgreSQL Schema
CREATE TABLE IF NOT EXISTS observations (
    id BIGSERIAL PRIMARY KEY,
    observation_id VARCHAR(50) UNIQUE NOT NULL,
    type VARCHAR(100) NOT NULL,
    value DOUBLE PRECISION NOT NULL,
    metadata JSONB,
    timestamp TIMESTAMPTZ DEFAULT NOW(),
    processed BOOLEAN DEFAULT FALSE
);

CREATE TABLE IF NOT EXISTS patterns (
    id BIGSERIAL PRIMARY KEY,
    pattern_key VARCHAR(200) UNIQUE NOT NULL,
    count INTEGER DEFAULT 0,
    sum_value DOUBLE PRECISION DEFAULT 0,
    mean_value DOUBLE PRECISION DEFAULT 0,
    min_value DOUBLE PRECISION,
    max_value DOUBLE PRECISION,
    std_dev DOUBLE PRECISION DEFAULT 0,
    confidence DOUBLE PRECISION DEFAULT 0.5,
    generation INTEGER DEFAULT 1,
    first_seen TIMESTAMPTZ,
    last_seen TIMESTAMPTZ,
    metadata JSONB
);

CREATE TABLE IF NOT EXISTS anomalies (
    id BIGSERIAL PRIMARY KEY,
    pattern_key VARCHAR(200) NOT NULL REFERENCES patterns(pattern_key),
    value DOUBLE PRECISION NOT NULL,
    expected_value DOUBLE PRECISION,
    z_score DOUBLE PRECISION,
    severity VARCHAR(20),
    timestamp TIMESTAMPTZ DEFAULT NOW(),
    acknowledged BOOLEAN DEFAULT FALSE
);

CREATE TABLE IF NOT EXISTS correlations (
    id BIGSERIAL PRIMARY KEY,
    pattern_a VARCHAR(200) NOT NULL,
    pattern_b VARCHAR(200) NOT NULL,
    co_occurrence_count INTEGER DEFAULT 0,
    correlation_strength DOUBLE PRECISION DEFAULT 0,
    first_seen TIMESTAMPTZ,
    last_seen TIMESTAMPTZ,
    UNIQUE(pattern_a, pattern_b)
);

CREATE TABLE IF NOT EXISTS sequences (
    id BIGSERIAL PRIMARY KEY,
    from_pattern VARCHAR(200) NOT NULL,
    to_pattern VARCHAR(200) NOT NULL,
    transition_count INTEGER DEFAULT 0,
    probability DOUBLE PRECISION DEFAULT 0,
    avg_interval_ms DOUBLE PRECISION,
    last_seen TIMESTAMPTZ,
    UNIQUE(from_pattern, to_pattern)
);

CREATE TABLE IF NOT EXISTS strategies (
    id BIGSERIAL PRIMARY KEY,
    strategy_id VARCHAR(50) UNIQUE NOT NULL,
    learning_rate DOUBLE PRECISION NOT NULL,
    memory_decay DOUBLE PRECISION NOT NULL,
    confidence_threshold DOUBLE PRECISION NOT NULL,
    prune_threshold DOUBLE PRECISION NOT NULL,
    fitness DOUBLE PRECISION DEFAULT 0,
    predictions INTEGER DEFAULT 0,
    correct_predictions INTEGER DEFAULT 0,
    generation INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS insights (
    id BIGSERIAL PRIMARY KEY,
    pattern_key VARCHAR(200) NOT NULL,
    insight_type VARCHAR(50) NOT NULL,
    description TEXT,
    confidence DOUBLE PRECISION,
    supporting_evidence JSONB,
    generation INTEGER,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS metrics (
    id BIGSERIAL PRIMARY KEY,
    timestamp TIMESTAMPTZ DEFAULT NOW(),
    cycle_number INTEGER,
    observations_total INTEGER,
    patterns_count INTEGER,
    avg_confidence DOUBLE PRECISION,
    anomalies_count INTEGER,
    active_strategy VARCHAR(50),
    strategy_fitness DOUBLE PRECISION,
    memory_usage_mb DOUBLE PRECISION,
    cycle_duration_ms DOUBLE PRECISION
);

CREATE TABLE IF NOT EXISTS neural_weights (
    id BIGSERIAL PRIMARY KEY,
    layer_id INTEGER NOT NULL,
    from_node INTEGER NOT NULL,
    to_node INTEGER NOT NULL,
    weight DOUBLE PRECISION NOT NULL,
    bias DOUBLE PRECISION DEFAULT 0,
    gradient DOUBLE PRECISION DEFAULT 0,
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(layer_id, from_node, to_node)
);

CREATE TABLE IF NOT EXISTS distributed_nodes (
    id BIGSERIAL PRIMARY KEY,
    node_id VARCHAR(50) UNIQUE NOT NULL,
    node_name VARCHAR(100),
    endpoint_url VARCHAR(500),
    status VARCHAR(20) DEFAULT 'unknown',
    last_heartbeat TIMESTAMPTZ,
    knowledge_version INTEGER DEFAULT 0,
    patterns_count INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS sync_log (
    id BIGSERIAL PRIMARY KEY,
    source_node VARCHAR(50) NOT NULL,
    target_node VARCHAR(50) NOT NULL,
    sync_type VARCHAR(50) NOT NULL,
    records_synced INTEGER DEFAULT 0,
    status VARCHAR(20),
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    error_message TEXT
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_observations_type ON observations(type);
CREATE INDEX IF NOT EXISTS idx_observations_timestamp ON observations(timestamp);
CREATE INDEX IF NOT EXISTS idx_patterns_confidence ON patterns(confidence);
CREATE INDEX IF NOT EXISTS idx_anomalies_severity ON anomalies(severity);
CREATE INDEX IF NOT EXISTS idx_metrics_timestamp ON metrics(timestamp);
"@
}

# ============================================================
# CONNECTION MANAGEMENT
# ============================================================
function Initialize-DatabaseConnection {
    <#
    .SYNOPSIS
    Initializes database connection based on configured provider.
    
    .PARAMETER Provider
    Database provider: SQLite, SQLServer, or PostgreSQL
    
    .PARAMETER ConnectionString
    Optional custom connection string (overrides other settings)
    #>
    [CmdletBinding()]
    param(
        [ValidateSet("SQLite", "SQLServer", "PostgreSQL")]
        [string]$Provider = $script:DbConfig.Provider,
        
        [string]$ConnectionString = $null
    )
    
    $script:DbConfig.Provider = $Provider
    
    Write-Host "[NEO-DB] Initializing $Provider connection..." -ForegroundColor Cyan
    
    switch ($Provider) {
        "SQLite" {
            # Check for PSSQLite module
            if (-not (Get-Module -ListAvailable -Name PSSQLite)) {
                Write-Host "[NEO-DB] Installing PSSQLite module..." -ForegroundColor Yellow
                Install-Module -Name PSSQLite -Force -Scope CurrentUser
            }
            Import-Module PSSQLite -Force
            
            $script:DbConfig.ConnectionString = $script:DbConfig.SQLitePath
            
            # Create database file if it doesn't exist
            if (-not (Test-Path $script:DbConfig.SQLitePath)) {
                Write-Host "[NEO-DB] Creating SQLite database at $($script:DbConfig.SQLitePath)" -ForegroundColor Yellow
            }
        }
        
        "SQLServer" {
            if ($ConnectionString) {
                $script:DbConfig.ConnectionString = $ConnectionString
            } else {
                if ($script:DbConfig.SQLIntegrated) {
                    $script:DbConfig.ConnectionString = "Server=$($script:DbConfig.SQLServer);Database=$($script:DbConfig.SQLDatabase);Integrated Security=True;Connection Timeout=$($script:DbConfig.ConnectionTimeout)"
                } else {
                    $script:DbConfig.ConnectionString = "Server=$($script:DbConfig.SQLServer);Database=$($script:DbConfig.SQLDatabase);User Id=$($script:DbConfig.SQLUser);Password=$($script:DbConfig.SQLPassword);Connection Timeout=$($script:DbConfig.ConnectionTimeout)"
                }
            }
        }
        
        "PostgreSQL" {
            # Check for Npgsql
            if (-not (Get-Module -ListAvailable -Name Npgsql)) {
                Write-Host "[NEO-DB] Installing Npgsql module..." -ForegroundColor Yellow
                Install-Module -Name Npgsql -Force -Scope CurrentUser
            }
            Import-Module Npgsql -Force
            
            if ($ConnectionString) {
                $script:DbConfig.ConnectionString = $ConnectionString
            } else {
                $script:DbConfig.ConnectionString = "Host=$($script:DbConfig.PGHost);Port=$($script:DbConfig.PGPort);Database=$($script:DbConfig.PGDatabase);Username=$($script:DbConfig.PGUser);Password=$($script:DbConfig.PGPassword);Pooling=true;Maximum Pool Size=$($script:DbConfig.MaxPoolSize)"
            }
        }
    }
    
    # Initialize schema if configured
    if ($script:DbConfig.AutoCreateSchema) {
        Initialize-DatabaseSchema
    }
    
    Write-Host "[NEO-DB] Database connection initialized successfully" -ForegroundColor Green
    return $true
}

function Initialize-DatabaseSchema {
    <#
    Creates all required tables if they don't exist.
    #>
    
    Write-Host "[NEO-DB] Initializing database schema..." -ForegroundColor Yellow
    
    $schemaScript = $script:Schema[$script:DbConfig.Provider]
    
    try {
        switch ($script:DbConfig.Provider) {
            "SQLite" {
                # Split by semicolon and execute each statement
                $statements = $schemaScript -split ';\s*\n' | Where-Object { $_.Trim() -ne '' }
                foreach ($stmt in $statements) {
                    Invoke-SqliteQuery -DataSource $script:DbConfig.ConnectionString -Query $stmt -ErrorAction SilentlyContinue
                }
            }
            
            "SQLServer" {
                Invoke-Sqlcmd -ConnectionString $script:DbConfig.ConnectionString -Query $schemaScript -ErrorAction Stop
            }
            
            "PostgreSQL" {
                Invoke-NpgsqlQuery -ConnectionString $script:DbConfig.ConnectionString -Query $schemaScript
            }
        }
        
        Write-Host "[NEO-DB] Schema initialization complete" -ForegroundColor Green
    } catch {
        Write-Host "[NEO-DB] Schema initialization error: $_" -ForegroundColor Red
        throw
    }
}

# ============================================================
# QUERY EXECUTION HELPERS
# ============================================================
function Invoke-NeoQuery {
    <#
    .SYNOPSIS
    Executes a query against the configured database.
    
    .PARAMETER Query
    SQL query to execute
    
    .PARAMETER Parameters
    Hashtable of parameter names and values
    
    .PARAMETER Scalar
    Return single scalar value
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Query,
        
        [hashtable]$Parameters = @{},
        
        [switch]$Scalar,
        
        [switch]$NonQuery
    )
    
    try {
        switch ($script:DbConfig.Provider) {
            "SQLite" {
                if ($NonQuery) {
                    Invoke-SqliteQuery -DataSource $script:DbConfig.ConnectionString -Query $Query -SqlParameters $Parameters
                    return
                }
                $result = Invoke-SqliteQuery -DataSource $script:DbConfig.ConnectionString -Query $Query -SqlParameters $Parameters
                if ($Scalar -and $result) {
                    return $result[0].PSObject.Properties.Value | Select-Object -First 1
                }
                return $result
            }
            
            "SQLServer" {
                # Convert parameters for SQL Server
                $sqlParams = @()
                foreach ($key in $Parameters.Keys) {
                    $sqlParams += "$key='$($Parameters[$key])'"
                }
                
                if ($NonQuery) {
                    Invoke-Sqlcmd -ConnectionString $script:DbConfig.ConnectionString -Query $Query -Variable $sqlParams
                    return
                }
                
                $result = Invoke-Sqlcmd -ConnectionString $script:DbConfig.ConnectionString -Query $Query -Variable $sqlParams
                if ($Scalar -and $result) {
                    return $result[0]
                }
                return $result
            }
            
            "PostgreSQL" {
                return Invoke-NpgsqlQuery -ConnectionString $script:DbConfig.ConnectionString -Query $Query -Parameters $Parameters -Scalar:$Scalar
            }
        }
    } catch {
        Write-Host "[NEO-DB] Query error: $_" -ForegroundColor Red
        Write-Host "[NEO-DB] Query was: $Query" -ForegroundColor DarkGray
        throw
    }
}

function Invoke-NpgsqlQuery {
    <#
    Helper function for PostgreSQL queries using Npgsql.
    #>
    param(
        [string]$ConnectionString,
        [string]$Query,
        [hashtable]$Parameters = @{},
        [switch]$Scalar
    )
    
    $connection = New-Object Npgsql.NpgsqlConnection($ConnectionString)
    $connection.Open()
    
    try {
        $command = $connection.CreateCommand()
        $command.CommandText = $Query
        
        foreach ($key in $Parameters.Keys) {
            [void]$command.Parameters.AddWithValue($key, $Parameters[$key])
        }
        
        if ($Scalar) {
            return $command.ExecuteScalar()
        }
        
        $reader = $command.ExecuteReader()
        $table = New-Object System.Data.DataTable
        $table.Load($reader)
        
        return $table
    } finally {
        $connection.Close()
    }
}

# ============================================================
# OBSERVATION OPERATIONS
# ============================================================
function Add-Observation {
    <#
    .SYNOPSIS
    Adds a new observation to the database.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Type,
        
        [Parameter(Mandatory)]
        [double]$Value,
        
        [hashtable]$Metadata = @{},
        
        [string]$ObservationId = [guid]::NewGuid().ToString()
    )
    
    $metadataJson = $Metadata | ConvertTo-Json -Compress
    
    $query = switch ($script:DbConfig.Provider) {
        "SQLite" {
            "INSERT INTO observations (observation_id, type, value, metadata) VALUES (@id, @type, @value, @metadata)"
        }
        "SQLServer" {
            "INSERT INTO observations (observation_id, type, value, metadata) VALUES (@id, @type, @value, @metadata)"
        }
        "PostgreSQL" {
            "INSERT INTO observations (observation_id, type, value, metadata) VALUES (@id, @type, @value, @metadata::jsonb)"
        }
    }
    
    Invoke-NeoQuery -Query $query -Parameters @{
        id = $ObservationId
        type = $Type
        value = $Value
        metadata = $metadataJson
    } -NonQuery
    
    return $ObservationId
}

function Get-UnprocessedObservations {
    <#
    .SYNOPSIS
    Retrieves unprocessed observations for learning.
    #>
    [CmdletBinding()]
    param(
        [int]$BatchSize = 100,
        [switch]$MarkAsProcessed
    )
    
    $query = switch ($script:DbConfig.Provider) {
        "SQLite" {
            "SELECT * FROM observations WHERE processed = 0 ORDER BY timestamp LIMIT $BatchSize"
        }
        "SQLServer" {
            "SELECT TOP $BatchSize * FROM observations WHERE processed = 0 ORDER BY timestamp"
        }
        "PostgreSQL" {
            "SELECT * FROM observations WHERE processed = FALSE ORDER BY timestamp LIMIT $BatchSize"
        }
    }
    
    $results = Invoke-NeoQuery -Query $query
    
    if ($MarkAsProcessed -and $results) {
        $ids = ($results | ForEach-Object { "'$($_.observation_id)'" }) -join ","
        $updateQuery = "UPDATE observations SET processed = 1 WHERE observation_id IN ($ids)"
        Invoke-NeoQuery -Query $updateQuery -NonQuery
    }
    
    return $results
}

# ============================================================
# PATTERN OPERATIONS
# ============================================================
function Save-Pattern {
    <#
    .SYNOPSIS
    Saves or updates a learned pattern in the database.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PatternKey,
        
        [int]$Count,
        [double]$SumValue,
        [double]$MeanValue,
        [double]$MinValue,
        [double]$MaxValue,
        [double]$StdDev,
        [double]$Confidence,
        [int]$Generation,
        [hashtable]$Metadata = @{}
    )
    
    $metadataJson = $Metadata | ConvertTo-Json -Compress
    $now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    # Upsert pattern
    $query = switch ($script:DbConfig.Provider) {
        "SQLite" {
            @"
INSERT INTO patterns (pattern_key, count, sum_value, mean_value, min_value, max_value, std_dev, confidence, generation, first_seen, last_seen, metadata)
VALUES (@key, @count, @sum, @mean, @min, @max, @std, @conf, @gen, @now, @now, @meta)
ON CONFLICT(pattern_key) DO UPDATE SET
    count = @count,
    sum_value = @sum,
    mean_value = @mean,
    min_value = @min,
    max_value = @max,
    std_dev = @std,
    confidence = @conf,
    generation = @gen,
    last_seen = @now,
    metadata = @meta
"@
        }
        "SQLServer" {
            @"
MERGE patterns AS target
USING (SELECT @key AS pattern_key) AS source
ON target.pattern_key = source.pattern_key
WHEN MATCHED THEN
    UPDATE SET count = @count, sum_value = @sum, mean_value = @mean, min_value = @min, max_value = @max, std_dev = @std, confidence = @conf, generation = @gen, last_seen = GETUTCDATE(), metadata = @meta
WHEN NOT MATCHED THEN
    INSERT (pattern_key, count, sum_value, mean_value, min_value, max_value, std_dev, confidence, generation, first_seen, last_seen, metadata)
    VALUES (@key, @count, @sum, @mean, @min, @max, @std, @conf, @gen, GETUTCDATE(), GETUTCDATE(), @meta);
"@
        }
        "PostgreSQL" {
            @"
INSERT INTO patterns (pattern_key, count, sum_value, mean_value, min_value, max_value, std_dev, confidence, generation, first_seen, last_seen, metadata)
VALUES (@key, @count, @sum, @mean, @min, @max, @std, @conf, @gen, NOW(), NOW(), @meta::jsonb)
ON CONFLICT (pattern_key) DO UPDATE SET
    count = @count,
    sum_value = @sum,
    mean_value = @mean,
    min_value = @min,
    max_value = @max,
    std_dev = @std,
    confidence = @conf,
    generation = @gen,
    last_seen = NOW(),
    metadata = @meta::jsonb
"@
        }
    }
    
    Invoke-NeoQuery -Query $query -Parameters @{
        key = $PatternKey
        count = $Count
        sum = $SumValue
        mean = $MeanValue
        min = $MinValue
        max = $MaxValue
        std = $StdDev
        conf = $Confidence
        gen = $Generation
        now = $now
        meta = $metadataJson
    } -NonQuery
}

function Get-Patterns {
    <#
    .SYNOPSIS
    Retrieves all learned patterns.
    #>
    [CmdletBinding()]
    param(
        [double]$MinConfidence = 0,
        [int]$Limit = 1000
    )
    
    $query = switch ($script:DbConfig.Provider) {
        "SQLite" {
            "SELECT * FROM patterns WHERE confidence >= $MinConfidence ORDER BY confidence DESC LIMIT $Limit"
        }
        "SQLServer" {
            "SELECT TOP $Limit * FROM patterns WHERE confidence >= $MinConfidence ORDER BY confidence DESC"
        }
        "PostgreSQL" {
            "SELECT * FROM patterns WHERE confidence >= $MinConfidence ORDER BY confidence DESC LIMIT $Limit"
        }
    }
    
    return Invoke-NeoQuery -Query $query
}

function Get-Pattern {
    <#
    .SYNOPSIS
    Retrieves a specific pattern by key.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PatternKey
    )
    
    $query = "SELECT * FROM patterns WHERE pattern_key = @key"
    return Invoke-NeoQuery -Query $query -Parameters @{ key = $PatternKey }
}

function Remove-Pattern {
    <#
    .SYNOPSIS
    Removes a pattern from the database.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PatternKey
    )
    
    $query = "DELETE FROM patterns WHERE pattern_key = @key"
    Invoke-NeoQuery -Query $query -Parameters @{ key = $PatternKey } -NonQuery
}

# ============================================================
# ANOMALY OPERATIONS
# ============================================================
function Add-Anomaly {
    <#
    .SYNOPSIS
    Records a detected anomaly.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PatternKey,
        
        [Parameter(Mandatory)]
        [double]$Value,
        
        [double]$ExpectedValue,
        [double]$ZScore,
        [string]$Severity = "MEDIUM"
    )
    
    $query = "INSERT INTO anomalies (pattern_key, value, expected_value, z_score, severity) VALUES (@key, @value, @expected, @zscore, @severity)"
    
    Invoke-NeoQuery -Query $query -Parameters @{
        key = $PatternKey
        value = $Value
        expected = $ExpectedValue
        zscore = $ZScore
        severity = $Severity
    } -NonQuery
}

function Get-Anomalies {
    <#
    .SYNOPSIS
    Retrieves anomalies with optional filtering.
    #>
    [CmdletBinding()]
    param(
        [string]$PatternKey,
        [string]$Severity,
        [int]$LastN = 100,
        [switch]$UnacknowledgedOnly
    )
    
    $whereClause = "WHERE 1=1"
    if ($PatternKey) { $whereClause += " AND pattern_key = '$PatternKey'" }
    if ($Severity) { $whereClause += " AND severity = '$Severity'" }
    if ($UnacknowledgedOnly) { $whereClause += " AND acknowledged = 0" }
    
    $query = switch ($script:DbConfig.Provider) {
        "SQLite" { "SELECT * FROM anomalies $whereClause ORDER BY timestamp DESC LIMIT $LastN" }
        "SQLServer" { "SELECT TOP $LastN * FROM anomalies $whereClause ORDER BY timestamp DESC" }
        "PostgreSQL" { "SELECT * FROM anomalies $whereClause ORDER BY timestamp DESC LIMIT $LastN" }
    }
    
    return Invoke-NeoQuery -Query $query
}

# ============================================================
# SEQUENCE OPERATIONS
# ============================================================
function Update-Sequence {
    <#
    .SYNOPSIS
    Updates or creates a sequence transition record.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FromPattern,
        
        [Parameter(Mandatory)]
        [string]$ToPattern,
        
        [double]$IntervalMs = 0
    )
    
    # Get current count for this transition
    $existing = Invoke-NeoQuery -Query "SELECT transition_count FROM sequences WHERE from_pattern = @from AND to_pattern = @to" -Parameters @{
        from = $FromPattern
        to = $ToPattern
    }
    
    # Get total transitions from this pattern
    $totalFromPattern = Invoke-NeoQuery -Query "SELECT SUM(transition_count) as total FROM sequences WHERE from_pattern = @from" -Parameters @{
        from = $FromPattern
    } -Scalar
    
    $newCount = if ($existing) { $existing.transition_count + 1 } else { 1 }
    $newTotal = if ($totalFromPattern) { $totalFromPattern + 1 } else { 1 }
    $probability = $newCount / $newTotal
    
    $query = switch ($script:DbConfig.Provider) {
        "SQLite" {
            @"
INSERT INTO sequences (from_pattern, to_pattern, transition_count, probability, avg_interval_ms, last_seen)
VALUES (@from, @to, 1, @prob, @interval, datetime('now'))
ON CONFLICT(from_pattern, to_pattern) DO UPDATE SET
    transition_count = transition_count + 1,
    probability = @prob,
    avg_interval_ms = (COALESCE(avg_interval_ms, 0) * transition_count + @interval) / (transition_count + 1),
    last_seen = datetime('now')
"@
        }
        "SQLServer" {
            @"
MERGE sequences AS target
USING (SELECT @from AS from_pattern, @to AS to_pattern) AS source
ON target.from_pattern = source.from_pattern AND target.to_pattern = source.to_pattern
WHEN MATCHED THEN
    UPDATE SET transition_count = transition_count + 1, probability = @prob, avg_interval_ms = (COALESCE(avg_interval_ms, 0) * transition_count + @interval) / (transition_count + 1), last_seen = GETUTCDATE()
WHEN NOT MATCHED THEN
    INSERT (from_pattern, to_pattern, transition_count, probability, avg_interval_ms, last_seen)
    VALUES (@from, @to, 1, @prob, @interval, GETUTCDATE());
"@
        }
        "PostgreSQL" {
            @"
INSERT INTO sequences (from_pattern, to_pattern, transition_count, probability, avg_interval_ms, last_seen)
VALUES (@from, @to, 1, @prob, @interval, NOW())
ON CONFLICT (from_pattern, to_pattern) DO UPDATE SET
    transition_count = sequences.transition_count + 1,
    probability = @prob,
    avg_interval_ms = (COALESCE(sequences.avg_interval_ms, 0) * sequences.transition_count + @interval) / (sequences.transition_count + 1),
    last_seen = NOW()
"@
        }
    }
    
    Invoke-NeoQuery -Query $query -Parameters @{
        from = $FromPattern
        to = $ToPattern
        prob = $probability
        interval = $IntervalMs
    } -NonQuery
    
    # Recalculate probabilities for all transitions from this pattern
    Update-SequenceProbabilities -FromPattern $FromPattern
}

function Update-SequenceProbabilities {
    <#
    Recalculates probabilities for all transitions from a pattern.
    #>
    param([string]$FromPattern)
    
    $total = Invoke-NeoQuery -Query "SELECT SUM(transition_count) as total FROM sequences WHERE from_pattern = @from" -Parameters @{ from = $FromPattern } -Scalar
    
    if ($total -and $total -gt 0) {
        $query = "UPDATE sequences SET probability = CAST(transition_count AS FLOAT) / $total WHERE from_pattern = @from"
        Invoke-NeoQuery -Query $query -Parameters @{ from = $FromPattern } -NonQuery
    }
}

function Get-NextPatternPrediction {
    <#
    .SYNOPSIS
    Gets the most likely next pattern based on learned sequences.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CurrentPattern,
        
        [int]$TopN = 5
    )
    
    $query = switch ($script:DbConfig.Provider) {
        "SQLite" { "SELECT to_pattern, probability, transition_count FROM sequences WHERE from_pattern = @from ORDER BY probability DESC LIMIT $TopN" }
        "SQLServer" { "SELECT TOP $TopN to_pattern, probability, transition_count FROM sequences WHERE from_pattern = @from ORDER BY probability DESC" }
        "PostgreSQL" { "SELECT to_pattern, probability, transition_count FROM sequences WHERE from_pattern = @from ORDER BY probability DESC LIMIT $TopN" }
    }
    
    return Invoke-NeoQuery -Query $query -Parameters @{ from = $CurrentPattern }
}

# ============================================================
# STRATEGY OPERATIONS
# ============================================================
function Save-Strategy {
    <#
    .SYNOPSIS
    Saves or updates a learning strategy.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$StrategyId,
        
        [double]$LearningRate,
        [double]$MemoryDecay,
        [double]$ConfidenceThreshold,
        [double]$PruneThreshold,
        [double]$Fitness = 0,
        [int]$Predictions = 0,
        [int]$CorrectPredictions = 0,
        [int]$Generation = 0,
        [bool]$IsActive = $false
    )
    
    $query = switch ($script:DbConfig.Provider) {
        "SQLite" {
            @"
INSERT INTO strategies (strategy_id, learning_rate, memory_decay, confidence_threshold, prune_threshold, fitness, predictions, correct_predictions, generation, is_active, updated_at)
VALUES (@id, @lr, @decay, @conf, @prune, @fitness, @pred, @correct, @gen, @active, datetime('now'))
ON CONFLICT(strategy_id) DO UPDATE SET
    learning_rate = @lr,
    memory_decay = @decay,
    confidence_threshold = @conf,
    prune_threshold = @prune,
    fitness = @fitness,
    predictions = @pred,
    correct_predictions = @correct,
    generation = @gen,
    is_active = @active,
    updated_at = datetime('now')
"@
        }
        "SQLServer" {
            @"
MERGE strategies AS target
USING (SELECT @id AS strategy_id) AS source
ON target.strategy_id = source.strategy_id
WHEN MATCHED THEN
    UPDATE SET learning_rate = @lr, memory_decay = @decay, confidence_threshold = @conf, prune_threshold = @prune, fitness = @fitness, predictions = @pred, correct_predictions = @correct, generation = @gen, is_active = @active, updated_at = GETUTCDATE()
WHEN NOT MATCHED THEN
    INSERT (strategy_id, learning_rate, memory_decay, confidence_threshold, prune_threshold, fitness, predictions, correct_predictions, generation, is_active, updated_at)
    VALUES (@id, @lr, @decay, @conf, @prune, @fitness, @pred, @correct, @gen, @active, GETUTCDATE());
"@
        }
        "PostgreSQL" {
            @"
INSERT INTO strategies (strategy_id, learning_rate, memory_decay, confidence_threshold, prune_threshold, fitness, predictions, correct_predictions, generation, is_active, updated_at)
VALUES (@id, @lr, @decay, @conf, @prune, @fitness, @pred, @correct, @gen, @active, NOW())
ON CONFLICT (strategy_id) DO UPDATE SET
    learning_rate = @lr,
    memory_decay = @decay,
    confidence_threshold = @conf,
    prune_threshold = @prune,
    fitness = @fitness,
    predictions = @pred,
    correct_predictions = @correct,
    generation = @gen,
    is_active = @active,
    updated_at = NOW()
"@
        }
    }
    
    Invoke-NeoQuery -Query $query -Parameters @{
        id = $StrategyId
        lr = $LearningRate
        decay = $MemoryDecay
        conf = $ConfidenceThreshold
        prune = $PruneThreshold
        fitness = $Fitness
        pred = $Predictions
        correct = $CorrectPredictions
        gen = $Generation
        active = if ($IsActive) { 1 } else { 0 }
    } -NonQuery
}

function Get-Strategies {
    <#
    .SYNOPSIS
    Retrieves all strategies, optionally sorted by fitness.
    #>
    [CmdletBinding()]
    param(
        [switch]$ActiveOnly,
        [switch]$OrderByFitness
    )
    
    $where = if ($ActiveOnly) { "WHERE is_active = 1" } else { "" }
    $order = if ($OrderByFitness) { "ORDER BY fitness DESC" } else { "ORDER BY created_at DESC" }
    
    return Invoke-NeoQuery -Query "SELECT * FROM strategies $where $order"
}

# ============================================================
# METRICS OPERATIONS
# ============================================================
function Add-MetricsSnapshot {
    <#
    .SYNOPSIS
    Records a metrics snapshot for monitoring.
    #>
    [CmdletBinding()]
    param(
        [int]$CycleNumber,
        [int]$ObservationsTotal,
        [int]$PatternsCount,
        [double]$AvgConfidence,
        [int]$AnomaliesCount,
        [string]$ActiveStrategy,
        [double]$StrategyFitness,
        [double]$MemoryUsageMB,
        [double]$CycleDurationMs
    )
    
    $query = @"
INSERT INTO metrics (cycle_number, observations_total, patterns_count, avg_confidence, anomalies_count, active_strategy, strategy_fitness, memory_usage_mb, cycle_duration_ms)
VALUES (@cycle, @obs, @patterns, @conf, @anomalies, @strategy, @fitness, @memory, @duration)
"@
    
    Invoke-NeoQuery -Query $query -Parameters @{
        cycle = $CycleNumber
        obs = $ObservationsTotal
        patterns = $PatternsCount
        conf = $AvgConfidence
        anomalies = $AnomaliesCount
        strategy = $ActiveStrategy
        fitness = $StrategyFitness
        memory = $MemoryUsageMB
        duration = $CycleDurationMs
    } -NonQuery
}

function Get-MetricsHistory {
    <#
    .SYNOPSIS
    Retrieves metrics history for visualization.
    #>
    [CmdletBinding()]
    param(
        [int]$LastN = 1000,
        [datetime]$Since
    )
    
    $where = if ($Since) { "WHERE timestamp >= '$($Since.ToString('yyyy-MM-dd HH:mm:ss'))'" } else { "" }
    
    $query = switch ($script:DbConfig.Provider) {
        "SQLite" { "SELECT * FROM metrics $where ORDER BY timestamp DESC LIMIT $LastN" }
        "SQLServer" { "SELECT TOP $LastN * FROM metrics $where ORDER BY timestamp DESC" }
        "PostgreSQL" { "SELECT * FROM metrics $where ORDER BY timestamp DESC LIMIT $LastN" }
    }
    
    return Invoke-NeoQuery -Query $query
}

# ============================================================
# EXPORT MODULE
# ============================================================
Export-ModuleMember -Function @(
    'Initialize-DatabaseConnection',
    'Initialize-DatabaseSchema',
    'Invoke-NeoQuery',
    'Add-Observation',
    'Get-UnprocessedObservations',
    'Save-Pattern',
    'Get-Patterns',
    'Get-Pattern',
    'Remove-Pattern',
    'Add-Anomaly',
    'Get-Anomalies',
    'Update-Sequence',
    'Get-NextPatternPrediction',
    'Save-Strategy',
    'Get-Strategies',
    'Add-MetricsSnapshot',
    'Get-MetricsHistory'
)
