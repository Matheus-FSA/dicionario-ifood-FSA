-- ============================================================================
-- PROJETO: Sistema de Gestao de Pedidos e Entregas - iFood
-- GRUPO: 2 - Fundacao Santo Andre
-- SGBD alvo: MySQL 8.0.36 ou superior | InnoDB | utf8mb4
-- Collation: utf8mb4_0900_ai_ci
-- Fonte: Especificacao de Requisitos e Regras de Negocio, versao 1.1,
--        principalmente secoes 1.3, 2, 3, 4, 5, 6.1, 6.2 e 6.3.
-- Modelo: DER_iFood_Grupo2_Final.png
--
-- IMPORTANTE:
-- 1) Executar em uma instancia MySQL 8.0.36+ com privilegios para criar
--    database, tabelas, views, rotinas, triggers e eventos.
-- 2) O DDL implementa as 22 entidades do modelo logico documentado.
-- 3) Regras que dependem de varias tabelas devem usar as procedures indicadas
--    neste arquivo; nao devem ser substituidas por gravacoes diretas da API.
-- 4) A aplicacao deve definir as variaveis de sessao @app_id_usuario,
--    @app_id_cliente, @app_id_entregador e @app_ip_origem antes de executar
--    operacoes auditaveis. No maximo um ator pode estar definido por sessao.
-- 5) CPF do cliente/entregador e armazenado cifrado + HMAC; a validacao do CPF
--    em texto puro deve ocorrer antes da cifragem usando fn_valida_cpf().
-- 6) Coordenadas: latitude/longitude em DECIMAL(9,6); dias da semana em
--    horario_funcionamento: 1=segunda-feira ... 7=domingo.
-- ============================================================================

CREATE DATABASE IF NOT EXISTS ifood_grupo2
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;
USE ifood_grupo2;

SET NAMES utf8mb4 COLLATE utf8mb4_0900_ai_ci;
SET SESSION time_zone = 'America/Sao_Paulo';
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SET SESSION innodb_lock_wait_timeout = 5;
SET SESSION sql_mode = 'STRICT_TRANS_TABLES,NO_ZERO_DATE,NO_ZERO_IN_DATE,ONLY_FULL_GROUP_BY';

-- ============================================================================
-- 1. TABELAS DE DOMINIO E CADASTRO
-- ============================================================================

CREATE TABLE IF NOT EXISTS cidade (
    id_cidade       INT UNSIGNED NOT NULL AUTO_INCREMENT,
    nome            VARCHAR(100) NOT NULL,
    uf              CHAR(2) NOT NULL,
    PRIMARY KEY (id_cidade),
    CONSTRAINT uk_cidade_nome_uf UNIQUE (nome, uf),
    CONSTRAINT chk_cidade_uf CHECK (CHAR_LENGTH(uf) = 2)
) ENGINE=InnoDB COMMENT='Municipios usados nos enderecos e restaurantes';

CREATE TABLE IF NOT EXISTS categoria_restaurante (
    id_categoria_restaurante INT UNSIGNED NOT NULL AUTO_INCREMENT,
    nome                     VARCHAR(100) NOT NULL,
    ativo                    TINYINT UNSIGNED NOT NULL DEFAULT 1,
    PRIMARY KEY (id_categoria_restaurante),
    CONSTRAINT uk_categoria_restaurante_nome UNIQUE (nome),
    CONSTRAINT chk_categoria_restaurante_ativo CHECK (ativo IN (0,1))
) ENGINE=InnoDB COMMENT='Categorias dos estabelecimentos parceiros';

CREATE TABLE IF NOT EXISTS forma_pagamento (
    id_forma_pagamento       INT UNSIGNED NOT NULL AUTO_INCREMENT,
    nome                     VARCHAR(80) NOT NULL,
    exige_pagamento_online   TINYINT UNSIGNED NOT NULL DEFAULT 1,
    ativo                    TINYINT UNSIGNED NOT NULL DEFAULT 1,
    PRIMARY KEY (id_forma_pagamento),
    CONSTRAINT uk_forma_pagamento_nome UNIQUE (nome),
    CONSTRAINT chk_forma_pagamento_online CHECK (exige_pagamento_online IN (0,1)),
    CONSTRAINT chk_forma_pagamento_ativo CHECK (ativo IN (0,1))
) ENGINE=InnoDB COMMENT='Formas de pagamento aceitas pela plataforma';

CREATE TABLE IF NOT EXISTS cupom (
    id_cupom                 INT UNSIGNED NOT NULL AUTO_INCREMENT,
    codigo                   VARCHAR(50) NOT NULL,
    tipo_desconto            VARCHAR(20) NOT NULL,
    valor_beneficio          DECIMAL(10,2) NOT NULL,
    valor_pedido_minimo      DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    data_inicio              DATETIME NOT NULL,
    data_fim                 DATETIME NOT NULL,
    limite_uso_por_cliente  INT UNSIGNED NOT NULL,
    ativo                    TINYINT UNSIGNED NOT NULL DEFAULT 1,
    PRIMARY KEY (id_cupom),
    CONSTRAINT uk_cupom_codigo UNIQUE (codigo),
    CONSTRAINT chk_cupom_tipo CHECK (tipo_desconto IN ('PERCENTUAL','VALOR_FIXO')),
    CONSTRAINT chk_cupom_beneficio CHECK (
        valor_beneficio > 0 AND
        (tipo_desconto = 'VALOR_FIXO' OR valor_beneficio <= 100)
    ),
    CONSTRAINT chk_cupom_minimo CHECK (valor_pedido_minimo >= 0),
    CONSTRAINT chk_cupom_periodo CHECK (data_fim >= data_inicio),
    CONSTRAINT chk_cupom_limite CHECK (limite_uso_por_cliente >= 1),
    CONSTRAINT chk_cupom_ativo CHECK (ativo IN (0,1))
) ENGINE=InnoDB COMMENT='Cupons promocionais';

CREATE TABLE IF NOT EXISTS cliente (
    id_cliente                   INT UNSIGNED NOT NULL AUTO_INCREMENT,
    nome                         VARCHAR(150) NOT NULL,
    cpf_hash                     CHAR(64) NOT NULL,
    cpf_cifrado                  VARBINARY(256) NULL,
    email                        VARCHAR(255) NULL,
    telefone_cifrado             VARBINARY(256) NULL,
    data_nascimento              DATE NULL,
    senha_hash                   VARCHAR(255) NOT NULL,
    data_consentimento           DATETIME NOT NULL,
    versao_termo_consentimento   VARCHAR(30) NOT NULL,
    data_revogacao_consentimento DATETIME NULL,
    data_anonimizacao            DATETIME NULL,
    ativo                        TINYINT UNSIGNED NOT NULL DEFAULT 1,
    PRIMARY KEY (id_cliente),
    CONSTRAINT uk_cliente_cpf_hash UNIQUE (cpf_hash),
    CONSTRAINT uk_cliente_email UNIQUE (email),
    CONSTRAINT chk_cliente_ativo CHECK (ativo IN (0,1)),
    CONSTRAINT chk_cliente_anonimizacao CHECK (
        data_anonimizacao IS NOT NULL OR
        (cpf_cifrado IS NOT NULL AND email IS NOT NULL AND
         telefone_cifrado IS NOT NULL AND data_nascimento IS NOT NULL)
    ),
    CONSTRAINT chk_cliente_revogacao CHECK (
        data_revogacao_consentimento IS NULL OR
        data_revogacao_consentimento >= data_consentimento
    ),
    KEY idx_cliente_ativo (ativo)
) ENGINE=InnoDB COMMENT='Consumidores cadastrados; CPF e telefone cifrados';

CREATE TABLE IF NOT EXISTS entregador (
    id_entregador       INT UNSIGNED NOT NULL AUTO_INCREMENT,
    nome                VARCHAR(150) NOT NULL,
    cpf_hash            CHAR(64) NOT NULL,
    cpf_cifrado         VARBINARY(256) NULL,
    telefone_cifrado    VARBINARY(256) NULL,
    tipo_veiculo        VARCHAR(20) NOT NULL,
    senha_hash          VARCHAR(255) NOT NULL,
    situacao            VARCHAR(20) NOT NULL DEFAULT 'DISPONIVEL',
    data_anonimizacao   DATETIME NULL,
    ativo               TINYINT UNSIGNED NOT NULL DEFAULT 1,
    PRIMARY KEY (id_entregador),
    CONSTRAINT uk_entregador_cpf_hash UNIQUE (cpf_hash),
    CONSTRAINT chk_entregador_veiculo CHECK (tipo_veiculo IN ('BICICLETA','MOTO','CARRO')),
    CONSTRAINT chk_entregador_situacao CHECK (situacao IN ('DISPONIVEL','EM_ENTREGA','OFFLINE','BLOQUEADO')),
    CONSTRAINT chk_entregador_ativo CHECK (ativo IN (0,1)),
    CONSTRAINT chk_entregador_anonimizacao CHECK (
        data_anonimizacao IS NOT NULL OR
        (cpf_cifrado IS NOT NULL AND telefone_cifrado IS NOT NULL)
    ),
    KEY idx_entregador_situacao_ativo (situacao, ativo)
) ENGINE=InnoDB COMMENT='Entregadores parceiros; CPF e telefone cifrados';

-- ============================================================================
-- 2. RESTAURANTES, USUARIOS E CARDAPIO
-- ============================================================================

CREATE TABLE IF NOT EXISTS restaurante (
    id_restaurante              INT UNSIGNED NOT NULL AUTO_INCREMENT,
    id_categoria_restaurante    INT UNSIGNED NOT NULL,
    id_cidade                   INT UNSIGNED NOT NULL,
    razao_social                VARCHAR(180) NOT NULL,
    nome_fantasia               VARCHAR(150) NOT NULL,
    cnpj                        CHAR(14) NOT NULL,
    telefone                    VARCHAR(20) NOT NULL,
    cep                         CHAR(8) NOT NULL,
    logradouro                  VARCHAR(150) NOT NULL,
    numero                      VARCHAR(20) NOT NULL,
    complemento                 VARCHAR(100) NULL,
    bairro                      VARCHAR(100) NOT NULL,
    latitude                    DECIMAL(9,6) NOT NULL,
    longitude                   DECIMAL(9,6) NOT NULL,
    valor_pedido_minimo         DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    raio_entrega_km             DECIMAL(8,2) NOT NULL,
    taxa_entrega_base           DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    taxa_entrega_por_km         DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    percentual_comissao         DECIMAL(5,2) NOT NULL DEFAULT 0.00,
    situacao                    VARCHAR(20) NOT NULL DEFAULT 'FECHADO',
    ativo                       TINYINT UNSIGNED NOT NULL DEFAULT 1,
    PRIMARY KEY (id_restaurante),
    CONSTRAINT uk_restaurante_cnpj UNIQUE (cnpj),
    CONSTRAINT fk_restaurante_categoria FOREIGN KEY (id_categoria_restaurante)
        REFERENCES categoria_restaurante (id_categoria_restaurante)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_restaurante_cidade FOREIGN KEY (id_cidade)
        REFERENCES cidade (id_cidade)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_restaurante_cnpj CHECK (cnpj REGEXP '^[0-9]{14}$'),
    CONSTRAINT chk_restaurante_pedido_minimo CHECK (valor_pedido_minimo >= 0),
    CONSTRAINT chk_restaurante_raio CHECK (raio_entrega_km > 0),
    CONSTRAINT chk_restaurante_taxas CHECK (taxa_entrega_base >= 0 AND taxa_entrega_por_km >= 0),
    CONSTRAINT chk_restaurante_comissao CHECK (percentual_comissao BETWEEN 0 AND 100),
    CONSTRAINT chk_restaurante_situacao CHECK (situacao IN ('ABERTO','FECHADO','SUSPENSO')),
    CONSTRAINT chk_restaurante_ativo CHECK (ativo IN (0,1)),
    KEY idx_restaurante_cidade (id_cidade),
    KEY idx_restaurante_situacao_ativo (situacao, ativo)
) ENGINE=InnoDB COMMENT='Estabelecimentos parceiros';

CREATE TABLE IF NOT EXISTS usuario (
    id_usuario       INT UNSIGNED NOT NULL AUTO_INCREMENT,
    id_restaurante   INT UNSIGNED NULL,
    nome             VARCHAR(150) NOT NULL,
    login            VARCHAR(100) NOT NULL,
    senha_hash       VARCHAR(255) NOT NULL,
    perfil           VARCHAR(20) NOT NULL,
    ativo            TINYINT UNSIGNED NOT NULL DEFAULT 1,
    PRIMARY KEY (id_usuario),
    CONSTRAINT uk_usuario_login UNIQUE (login),
    CONSTRAINT fk_usuario_restaurante FOREIGN KEY (id_restaurante)
        REFERENCES restaurante (id_restaurante)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_usuario_perfil CHECK (perfil IN ('SUPORTE','GERENTE','ADMINISTRADOR','RESTAURANTE')),
    CONSTRAINT chk_usuario_restaurante_perfil CHECK (
        (perfil = 'RESTAURANTE' AND id_restaurante IS NOT NULL) OR
        (perfil <> 'RESTAURANTE' AND id_restaurante IS NULL)
    ),
    CONSTRAINT chk_usuario_ativo CHECK (ativo IN (0,1)),
    KEY idx_usuario_restaurante (id_restaurante)
) ENGINE=InnoDB COMMENT='Usuarios internos e usuarios dos restaurantes parceiros';

CREATE TABLE IF NOT EXISTS endereco_cliente (
    id_endereco_cliente  INT UNSIGNED NOT NULL AUTO_INCREMENT,
    id_cliente           INT UNSIGNED NOT NULL,
    id_cidade            INT UNSIGNED NOT NULL,
    apelido              VARCHAR(60) NOT NULL,
    logradouro           VARCHAR(150) NOT NULL,
    numero               VARCHAR(20) NOT NULL,
    complemento          VARCHAR(100) NULL,
    bairro               VARCHAR(100) NOT NULL,
    cep                  CHAR(8) NOT NULL,
    latitude             DECIMAL(9,6) NOT NULL,
    longitude            DECIMAL(9,6) NOT NULL,
    principal            TINYINT UNSIGNED NOT NULL DEFAULT 0,
    ativo                TINYINT UNSIGNED NOT NULL DEFAULT 1,
    id_cliente_principal_ativo INT UNSIGNED
        GENERATED ALWAYS AS (CASE WHEN principal = 1 AND ativo = 1 THEN id_cliente ELSE NULL END) STORED,
    PRIMARY KEY (id_endereco_cliente),
    CONSTRAINT fk_endereco_cliente_cliente FOREIGN KEY (id_cliente)
        REFERENCES cliente (id_cliente)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_endereco_cliente_cidade FOREIGN KEY (id_cidade)
        REFERENCES cidade (id_cidade)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT uk_endereco_id_cliente UNIQUE (id_endereco_cliente, id_cliente),
    CONSTRAINT uk_endereco_principal_ativo UNIQUE (id_cliente_principal_ativo),
    CONSTRAINT chk_endereco_cep CHECK (cep REGEXP '^[0-9]{8}$'),
    CONSTRAINT chk_endereco_principal CHECK (principal IN (0,1)),
    CONSTRAINT chk_endereco_ativo CHECK (ativo IN (0,1)),
    KEY idx_endereco_cliente (id_cliente),
    KEY idx_endereco_cidade (id_cidade)
) ENGINE=InnoDB COMMENT='Enderecos dos clientes; coluna gerada garante no maximo um principal ativo';

CREATE TABLE IF NOT EXISTS horario_funcionamento (
    id_horario_funcionamento INT UNSIGNED NOT NULL AUTO_INCREMENT,
    id_restaurante           INT UNSIGNED NOT NULL,
    dia_semana               TINYINT UNSIGNED NOT NULL COMMENT '1=segunda-feira ... 7=domingo',
    hora_abertura             TIME NOT NULL,
    hora_fechamento            TIME NOT NULL,
    PRIMARY KEY (id_horario_funcionamento),
    CONSTRAINT fk_horario_restaurante FOREIGN KEY (id_restaurante)
        REFERENCES restaurante (id_restaurante)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT uk_horario_restaurante_dia_abertura UNIQUE (id_restaurante, dia_semana, hora_abertura),
    CONSTRAINT chk_horario_dia CHECK (dia_semana BETWEEN 1 AND 7),
    CONSTRAINT chk_horario_intervalo CHECK (hora_abertura < hora_fechamento),
    KEY idx_horario_restaurante_dia (id_restaurante, dia_semana)
) ENGINE=InnoDB COMMENT='Janelas de funcionamento; intervalos que cruzam meia-noite devem ser divididos';

CREATE TABLE IF NOT EXISTS categoria_produto (
    id_categoria_produto INT UNSIGNED NOT NULL AUTO_INCREMENT,
    id_restaurante       INT UNSIGNED NOT NULL,
    nome                 VARCHAR(100) NOT NULL,
    ativo                TINYINT UNSIGNED NOT NULL DEFAULT 1,
    PRIMARY KEY (id_categoria_produto),
    CONSTRAINT fk_categoria_produto_restaurante FOREIGN KEY (id_restaurante)
        REFERENCES restaurante (id_restaurante)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT uk_categoria_produto_id_rest UNIQUE (id_categoria_produto, id_restaurante),
    CONSTRAINT uk_categoria_produto_nome UNIQUE (id_restaurante, nome),
    CONSTRAINT chk_categoria_produto_ativo CHECK (ativo IN (0,1)),
    KEY idx_categoria_produto_restaurante (id_restaurante)
) ENGINE=InnoDB COMMENT='Secoes do cardapio vinculadas a um restaurante';

DELIMITER $$

CREATE TRIGGER trg_horario_funcionamento_bi
BEFORE INSERT ON horario_funcionamento
FOR EACH ROW
BEGIN
    DECLARE v_sobreposicao INT DEFAULT 0;
    SELECT COUNT(*) INTO v_sobreposicao
    FROM horario_funcionamento h
    WHERE h.id_restaurante = NEW.id_restaurante
      AND h.dia_semana = NEW.dia_semana
      AND NEW.hora_abertura < h.hora_fechamento
      AND h.hora_abertura < NEW.hora_fechamento;
    IF v_sobreposicao > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Horario de funcionamento sobreposto no mesmo dia';
    END IF;
END$$

CREATE TRIGGER trg_horario_funcionamento_bu
BEFORE UPDATE ON horario_funcionamento
FOR EACH ROW
BEGIN
    DECLARE v_sobreposicao INT DEFAULT 0;
    SELECT COUNT(*) INTO v_sobreposicao
    FROM horario_funcionamento h
    WHERE h.id_restaurante = NEW.id_restaurante
      AND h.dia_semana = NEW.dia_semana
      AND h.id_horario_funcionamento <> OLD.id_horario_funcionamento
      AND NEW.hora_abertura < h.hora_fechamento
      AND h.hora_abertura < NEW.hora_fechamento;
    IF v_sobreposicao > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Horario de funcionamento sobreposto no mesmo dia';
    END IF;
END$$

DELIMITER ;

CREATE TABLE IF NOT EXISTS produto (
    id_produto            INT UNSIGNED NOT NULL AUTO_INCREMENT,
    id_restaurante        INT UNSIGNED NOT NULL,
    id_categoria_produto  INT UNSIGNED NOT NULL,
    nome                  VARCHAR(150) NOT NULL,
    descricao             VARCHAR(500) NULL,
    preco_tabela          DECIMAL(10,2) NOT NULL,
    alcoolico             TINYINT UNSIGNED NOT NULL DEFAULT 0,
    disponivel            TINYINT UNSIGNED NOT NULL DEFAULT 1,
    ativo                 TINYINT UNSIGNED NOT NULL DEFAULT 1,
    PRIMARY KEY (id_produto),
    CONSTRAINT fk_produto_restaurante FOREIGN KEY (id_restaurante)
        REFERENCES restaurante (id_restaurante)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_produto_categoria_restaurante FOREIGN KEY (id_categoria_produto, id_restaurante)
        REFERENCES categoria_produto (id_categoria_produto, id_restaurante)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_produto_preco CHECK (preco_tabela > 0),
    CONSTRAINT chk_produto_alcoolico CHECK (alcoolico IN (0,1)),
    CONSTRAINT chk_produto_disponivel CHECK (disponivel IN (0,1)),
    CONSTRAINT chk_produto_ativo CHECK (ativo IN (0,1)),
    KEY idx_produto_restaurante (id_restaurante),
    KEY idx_produto_categoria_restaurante (id_categoria_produto, id_restaurante),
    KEY idx_produto_disponibilidade (ativo, disponivel)
) ENGINE=InnoDB COMMENT='Itens comercializados no cardapio';

CREATE TABLE IF NOT EXISTS historico_preco (
    id_historico_preco INT UNSIGNED NOT NULL AUTO_INCREMENT,
    id_produto         INT UNSIGNED NOT NULL,
    id_usuario         INT UNSIGNED NOT NULL,
    preco_anterior     DECIMAL(10,2) NOT NULL,
    preco_novo         DECIMAL(10,2) NOT NULL,
    data_alteracao     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_historico_preco),
    CONSTRAINT fk_historico_preco_produto FOREIGN KEY (id_produto)
        REFERENCES produto (id_produto)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_historico_preco_usuario FOREIGN KEY (id_usuario)
        REFERENCES usuario (id_usuario)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_historico_preco_anterior CHECK (preco_anterior > 0),
    CONSTRAINT chk_historico_preco_novo CHECK (preco_novo > 0),
    KEY idx_historico_preco_produto (id_produto),
    KEY idx_historico_preco_data (data_alteracao)
) ENGINE=InnoDB COMMENT='Historico imutavel de alteracoes do preco de tabela';

-- ============================================================================
-- 3. PEDIDOS, ITENS, PAGAMENTOS E CICLO DE VIDA
-- ============================================================================

CREATE TABLE IF NOT EXISTS pedido (
    id_pedido                    INT UNSIGNED NOT NULL AUTO_INCREMENT,
    id_cliente                   INT UNSIGNED NOT NULL,
    id_restaurante               INT UNSIGNED NOT NULL,
    id_endereco_cliente          INT UNSIGNED NOT NULL,
    id_cupom                     INT UNSIGNED NULL,
    data_pedido                  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    situacao                     VARCHAR(20) NOT NULL DEFAULT 'CRIADO',
    taxa_entrega                 DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    valor_desconto               DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    percentual_comissao_aplicado DECIMAL(5,2) NOT NULL DEFAULT 0.00,
    motivo_cancelamento          VARCHAR(255) NULL,
    origem_cancelamento          VARCHAR(20) NULL,
    id_usuario_cancelamento      INT UNSIGNED NULL,
    data_cancelamento            DATETIME NULL,
    PRIMARY KEY (id_pedido),
    CONSTRAINT fk_pedido_cliente FOREIGN KEY (id_cliente)
        REFERENCES cliente (id_cliente)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_pedido_restaurante FOREIGN KEY (id_restaurante)
        REFERENCES restaurante (id_restaurante)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_pedido_endereco_cliente FOREIGN KEY (id_endereco_cliente, id_cliente)
        REFERENCES endereco_cliente (id_endereco_cliente, id_cliente)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_pedido_cupom FOREIGN KEY (id_cupom)
        REFERENCES cupom (id_cupom)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_pedido_usuario_cancelamento FOREIGN KEY (id_usuario_cancelamento)
        REFERENCES usuario (id_usuario)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_pedido_situacao CHECK (situacao IN ('CRIADO','CONFIRMADO','EM_PREPARO','PRONTO','EM_ROTA','ENTREGUE','CANCELADO')),
    CONSTRAINT chk_pedido_taxa CHECK (taxa_entrega >= 0),
    CONSTRAINT chk_pedido_desconto CHECK (valor_desconto >= 0),
    CONSTRAINT chk_pedido_comissao CHECK (percentual_comissao_aplicado BETWEEN 0 AND 100),
    CONSTRAINT chk_pedido_origem_cancelamento CHECK (
        origem_cancelamento IS NULL OR origem_cancelamento IN ('CLIENTE','RESTAURANTE','SUPORTE','SISTEMA')
    ),
    CONSTRAINT chk_pedido_cancelamento_suporte CHECK (
        origem_cancelamento <> 'SUPORTE' OR id_usuario_cancelamento IS NOT NULL
    ),
    KEY idx_pedido_data (data_pedido),
    KEY idx_pedido_cliente (id_cliente),
    KEY idx_pedido_restaurante (id_restaurante),
    KEY idx_pedido_situacao (situacao),
    KEY idx_pedido_cupom_cliente (id_cupom, id_cliente)
) ENGINE=InnoDB COMMENT='Pedidos; subtotal, valor total e comissao sao calculados por views';

CREATE TABLE IF NOT EXISTS item_pedido (
    id_item_pedido        INT UNSIGNED NOT NULL AUTO_INCREMENT,
    id_pedido             INT UNSIGNED NOT NULL,
    id_produto            INT UNSIGNED NOT NULL,
    quantidade            INT UNSIGNED NOT NULL,
    preco_unitario_venda  DECIMAL(10,2) NOT NULL,
    observacao            VARCHAR(255) NULL,
    PRIMARY KEY (id_item_pedido),
    CONSTRAINT fk_item_pedido_pedido FOREIGN KEY (id_pedido)
        REFERENCES pedido (id_pedido)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_item_pedido_produto FOREIGN KEY (id_produto)
        REFERENCES produto (id_produto)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT uk_item_pedido_produto UNIQUE (id_pedido, id_produto),
    CONSTRAINT chk_item_pedido_quantidade CHECK (quantidade > 0),
    CONSTRAINT chk_item_pedido_preco CHECK (preco_unitario_venda > 0),
    KEY idx_item_pedido_pedido (id_pedido),
    KEY idx_item_pedido_produto (id_produto)
) ENGINE=InnoDB COMMENT='Entidade associativa entre pedido e produto; conserva preco no momento da venda';

CREATE TABLE IF NOT EXISTS pagamento (
    id_pagamento             INT UNSIGNED NOT NULL AUTO_INCREMENT,
    id_pedido                INT UNSIGNED NOT NULL,
    id_forma_pagamento       INT UNSIGNED NOT NULL,
    valor                    DECIMAL(10,2) NOT NULL,
    situacao                 VARCHAR(20) NOT NULL DEFAULT 'PENDENTE',
    token_cartao             VARCHAR(512) NULL,
    ultimos_digitos          CHAR(4) NULL,
    codigo_transacao_gateway VARCHAR(150) NULL,
    data_pagamento           DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_pagamento),
    CONSTRAINT fk_pagamento_pedido FOREIGN KEY (id_pedido)
        REFERENCES pedido (id_pedido)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_pagamento_forma FOREIGN KEY (id_forma_pagamento)
        REFERENCES forma_pagamento (id_forma_pagamento)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_pagamento_valor CHECK (valor > 0),
    CONSTRAINT chk_pagamento_situacao CHECK (situacao IN ('PENDENTE','APROVADO','RECUSADO','ESTORNADO')),
    CONSTRAINT chk_pagamento_ultimos_digitos CHECK (ultimos_digitos IS NULL OR ultimos_digitos REGEXP '^[0-9]{4}$'),
    KEY idx_pagamento_pedido (id_pedido),
    KEY idx_pagamento_forma (id_forma_pagamento)
) ENGINE=InnoDB COMMENT='Registros de pagamento; nao armazena numero completo do cartao nem CVV';

CREATE TABLE IF NOT EXISTS historico_status_pedido (
    id_historico_status_pedido INT UNSIGNED NOT NULL AUTO_INCREMENT,
    id_pedido                  INT UNSIGNED NOT NULL,
    id_usuario                 INT UNSIGNED NULL,
    situacao_anterior          VARCHAR(20) NULL,
    situacao_nova              VARCHAR(20) NOT NULL,
    data_mudanca               DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_historico_status_pedido),
    CONSTRAINT fk_historico_status_pedido FOREIGN KEY (id_pedido)
        REFERENCES pedido (id_pedido)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_historico_status_usuario FOREIGN KEY (id_usuario)
        REFERENCES usuario (id_usuario)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_historico_status_anterior CHECK (
        situacao_anterior IS NULL OR situacao_anterior IN ('CRIADO','CONFIRMADO','EM_PREPARO','PRONTO','EM_ROTA','ENTREGUE','CANCELADO')
    ),
    CONSTRAINT chk_historico_status_nova CHECK (situacao_nova IN ('CRIADO','CONFIRMADO','EM_PREPARO','PRONTO','EM_ROTA','ENTREGUE','CANCELADO')),
    KEY idx_historico_status_pedido (id_pedido),
    KEY idx_historico_status_data (data_mudanca)
) ENGINE=InnoDB COMMENT='Trilha de alteracoes do ciclo de vida do pedido';

CREATE TABLE IF NOT EXISTS estorno (
    id_estorno        INT UNSIGNED NOT NULL AUTO_INCREMENT,
    id_pagamento      INT UNSIGNED NOT NULL,
    id_usuario        INT UNSIGNED NULL,
    valor             DECIMAL(10,2) NOT NULL,
    motivo            VARCHAR(255) NULL,
    situacao          VARCHAR(20) NOT NULL DEFAULT 'SOLICITADO',
    data_solicitacao  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    data_conclusao    DATETIME NULL,
    PRIMARY KEY (id_estorno),
    CONSTRAINT fk_estorno_pagamento FOREIGN KEY (id_pagamento)
        REFERENCES pagamento (id_pagamento)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_estorno_usuario FOREIGN KEY (id_usuario)
        REFERENCES usuario (id_usuario)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_estorno_valor CHECK (valor > 0),
    CONSTRAINT chk_estorno_situacao CHECK (situacao IN ('SOLICITADO','EM_ANALISE','APROVADO','CONCLUIDO','NEGADO')),
    CONSTRAINT chk_estorno_datas CHECK (data_conclusao IS NULL OR data_conclusao >= data_solicitacao),
    KEY idx_estorno_pagamento (id_pagamento),
    KEY idx_estorno_data (data_solicitacao)
) ENGINE=InnoDB COMMENT='Estornos parciais ou integrais associados a pagamentos';

CREATE TABLE IF NOT EXISTS entrega (
    id_entrega             INT UNSIGNED NOT NULL AUTO_INCREMENT,
    id_pedido              INT UNSIGNED NOT NULL,
    id_entregador          INT UNSIGNED NOT NULL,
    data_atribuicao        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    data_coleta            DATETIME NULL,
    data_entrega           DATETIME NULL,
    distancia_km           DECIMAL(8,2) NULL,
    maioridade_conferida   TINYINT UNSIGNED NOT NULL DEFAULT 0,
    situacao               VARCHAR(20) NOT NULL DEFAULT 'ATRIBUIDA',
    PRIMARY KEY (id_entrega),
    CONSTRAINT uk_entrega_pedido UNIQUE (id_pedido),
    CONSTRAINT fk_entrega_pedido FOREIGN KEY (id_pedido)
        REFERENCES pedido (id_pedido)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_entrega_entregador FOREIGN KEY (id_entregador)
        REFERENCES entregador (id_entregador)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_entrega_distancia CHECK (distancia_km IS NULL OR distancia_km >= 0),
    CONSTRAINT chk_entrega_maioridade CHECK (maioridade_conferida IN (0,1)),
    CONSTRAINT chk_entrega_situacao CHECK (situacao IN ('ATRIBUIDA','COLETADA','CONCLUIDA','CANCELADA')),
    KEY idx_entrega_entregador (id_entregador),
    KEY idx_entrega_situacao (situacao)
) ENGINE=InnoDB COMMENT='Execucao da entrega; no maximo uma entrega por pedido';

CREATE TABLE IF NOT EXISTS avaliacao (
    id_avaliacao       INT UNSIGNED NOT NULL AUTO_INCREMENT,
    id_pedido          INT UNSIGNED NOT NULL,
    nota_restaurante   TINYINT UNSIGNED NOT NULL,
    nota_entrega       TINYINT UNSIGNED NOT NULL,
    comentario         VARCHAR(1000) NULL,
    data_avaliacao     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_avaliacao),
    CONSTRAINT uk_avaliacao_pedido UNIQUE (id_pedido),
    CONSTRAINT fk_avaliacao_pedido FOREIGN KEY (id_pedido)
        REFERENCES pedido (id_pedido)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_avaliacao_nota_restaurante CHECK (nota_restaurante BETWEEN 1 AND 5),
    CONSTRAINT chk_avaliacao_nota_entrega CHECK (nota_entrega BETWEEN 1 AND 5),
    KEY idx_avaliacao_data (data_avaliacao)
) ENGINE=InnoDB COMMENT='Avaliacao unica por pedido entregue';

-- ============================================================================
-- 4. AUDITORIA E DIREITOS DO TITULAR (LGPD)
-- ============================================================================

CREATE TABLE IF NOT EXISTS log_auditoria (
    id_log_auditoria      BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    id_usuario            INT UNSIGNED NULL,
    id_cliente            INT UNSIGNED NULL,
    id_entregador         INT UNSIGNED NULL,
    operacao              VARCHAR(20) NOT NULL,
    tabela_afetada        VARCHAR(64) NOT NULL,
    id_registro_afetado   BIGINT UNSIGNED NOT NULL,
    valor_anterior        JSON NULL,
    valor_novo            JSON NULL,
    data_evento           DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ip_origem             VARCHAR(45) NOT NULL DEFAULT 'NAO_INFORMADO',
    PRIMARY KEY (id_log_auditoria),
    CONSTRAINT fk_log_auditoria_usuario FOREIGN KEY (id_usuario)
        REFERENCES usuario (id_usuario)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_log_auditoria_cliente FOREIGN KEY (id_cliente)
        REFERENCES cliente (id_cliente)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_log_auditoria_entregador FOREIGN KEY (id_entregador)
        REFERENCES entregador (id_entregador)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_log_auditoria_operacao CHECK (operacao IN ('LOGIN','LOGOUT','LOGIN_FALHO','ACESSO_NEGADO','INSERT','UPDATE','DELETE_LOGICO')),
    CONSTRAINT chk_log_auditoria_um_ator CHECK (
        (id_usuario IS NOT NULL) + (id_cliente IS NOT NULL) + (id_entregador IS NOT NULL) <= 1
    ),
    KEY idx_log_auditoria_data (data_evento),
    KEY idx_log_auditoria_registro (id_registro_afetado),
    KEY idx_log_auditoria_tabela_registro (tabela_afetada, id_registro_afetado)
) ENGINE=InnoDB COMMENT='Log append-only; valores pessoais devem ser mascarados';

CREATE TABLE IF NOT EXISTS solicitacao_titular (
    id_solicitacao_titular INT UNSIGNED NOT NULL AUTO_INCREMENT,
    id_cliente             INT UNSIGNED NULL,
    id_entregador          INT UNSIGNED NULL,
    id_usuario             INT UNSIGNED NULL,
    tipo                   VARCHAR(30) NOT NULL,
    situacao               VARCHAR(20) NOT NULL DEFAULT 'ABERTA',
    data_solicitacao       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    data_conclusao         DATETIME NULL,
    PRIMARY KEY (id_solicitacao_titular),
    CONSTRAINT fk_solicitacao_cliente FOREIGN KEY (id_cliente)
        REFERENCES cliente (id_cliente)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_solicitacao_entregador FOREIGN KEY (id_entregador)
        REFERENCES entregador (id_entregador)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_solicitacao_usuario FOREIGN KEY (id_usuario)
        REFERENCES usuario (id_usuario)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_solicitacao_um_titular CHECK (
        (id_cliente IS NOT NULL) + (id_entregador IS NOT NULL) = 1
    ),
    CONSTRAINT chk_solicitacao_tipo CHECK (tipo IN ('CONFIRMACAO','CORRECAO','EXPORTACAO','ANONIMIZACAO','REVOGACAO_CONSENTIMENTO')),
    CONSTRAINT chk_solicitacao_situacao CHECK (situacao IN ('ABERTA','EM_ATENDIMENTO','CONCLUIDA','NEGADA')),
    CONSTRAINT chk_solicitacao_datas CHECK (data_conclusao IS NULL OR data_conclusao >= data_solicitacao),
    KEY idx_solicitacao_cliente (id_cliente),
    KEY idx_solicitacao_entregador (id_entregador),
    KEY idx_solicitacao_situacao (situacao)
) ENGINE=InnoDB COMMENT='Solicitacoes de direitos LGPD por clientes ou entregadores';

-- ============================================================================
-- 5. DADOS DE REFERENCIA INICIAIS
-- ============================================================================

INSERT INTO forma_pagamento (nome, exige_pagamento_online, ativo) VALUES
 ('CARTAO_CREDITO', 1, 1),
 ('CARTAO_DEBITO', 1, 1),
 ('PIX', 1, 1),
 ('VALE_REFEICAO_ALIMENTACAO', 1, 1),
 ('PAGAMENTO_NA_ENTREGA', 0, 1)
AS novo
ON DUPLICATE KEY UPDATE
 exige_pagamento_online = novo.exige_pagamento_online,
 ativo = novo.ativo;

-- ============================================================================
-- 6. FUNCOES AUXILIARES
-- ============================================================================

DELIMITER $$

CREATE FUNCTION fn_valida_cpf(p_cpf VARCHAR(11))
RETURNS TINYINT
DETERMINISTIC
NO SQL
BEGIN
    DECLARE v_i INT DEFAULT 1;
    DECLARE v_soma INT DEFAULT 0;
    DECLARE v_d1 INT DEFAULT 0;
    DECLARE v_d2 INT DEFAULT 0;
    DECLARE v_resto INT DEFAULT 0;

    IF p_cpf IS NULL OR p_cpf NOT REGEXP '^[0-9]{11}$' THEN
        RETURN 0;
    END IF;
    IF p_cpf REGEXP '^([0-9])\\1{10}$' THEN
        RETURN 0;
    END IF;

    SET v_i = 1;
    WHILE v_i <= 9 DO
        SET v_soma = v_soma + CAST(SUBSTRING(p_cpf, v_i, 1) AS UNSIGNED) * (11 - v_i);
        SET v_i = v_i + 1;
    END WHILE;
    SET v_resto = (v_soma * 10) MOD 11;
    SET v_d1 = IF(v_resto = 10, 0, v_resto);
    IF v_d1 <> CAST(SUBSTRING(p_cpf, 10, 1) AS UNSIGNED) THEN
        RETURN 0;
    END IF;

    SET v_soma = 0;
    SET v_i = 1;
    WHILE v_i <= 10 DO
        SET v_soma = v_soma + CAST(SUBSTRING(p_cpf, v_i, 1) AS UNSIGNED) * (12 - v_i);
        SET v_i = v_i + 1;
    END WHILE;
    SET v_resto = (v_soma * 10) MOD 11;
    SET v_d2 = IF(v_resto = 10, 0, v_resto);
    RETURN (v_d2 = CAST(SUBSTRING(p_cpf, 11, 1) AS UNSIGNED));
END$$

CREATE FUNCTION fn_valida_cnpj(p_cnpj VARCHAR(14))
RETURNS TINYINT
DETERMINISTIC
NO SQL
BEGIN
    DECLARE v_i INT DEFAULT 1;
    DECLARE v_soma INT DEFAULT 0;
    DECLARE v_resto INT DEFAULT 0;
    DECLARE v_d1 INT DEFAULT 0;
    DECLARE v_d2 INT DEFAULT 0;
    DECLARE v_peso INT DEFAULT 0;

    IF p_cnpj IS NULL OR p_cnpj NOT REGEXP '^[0-9]{14}$' THEN
        RETURN 0;
    END IF;
    IF p_cnpj REGEXP '^([0-9])\\1{13}$' THEN
        RETURN 0;
    END IF;

    SET v_i = 1;
    WHILE v_i <= 12 DO
        SET v_peso = IF(v_i <= 4, 6 - v_i, 14 - v_i);
        SET v_soma = v_soma + CAST(SUBSTRING(p_cnpj, v_i, 1) AS UNSIGNED) * v_peso;
        SET v_i = v_i + 1;
    END WHILE;
    SET v_resto = v_soma MOD 11;
    SET v_d1 = IF(v_resto < 2, 0, 11 - v_resto);
    IF v_d1 <> CAST(SUBSTRING(p_cnpj, 13, 1) AS UNSIGNED) THEN
        RETURN 0;
    END IF;

    SET v_soma = 0;
    SET v_i = 1;
    WHILE v_i <= 13 DO
        SET v_peso = IF(v_i <= 5, 7 - v_i, 15 - v_i);
        SET v_soma = v_soma + CAST(SUBSTRING(p_cnpj, v_i, 1) AS UNSIGNED) * v_peso;
        SET v_i = v_i + 1;
    END WHILE;
    SET v_resto = v_soma MOD 11;
    SET v_d2 = IF(v_resto < 2, 0, 11 - v_resto);
    RETURN (v_d2 = CAST(SUBSTRING(p_cnpj, 14, 1) AS UNSIGNED));
END$$

CREATE FUNCTION fn_distancia_km(
    p_lat1 DECIMAL(9,6), p_lon1 DECIMAL(9,6),
    p_lat2 DECIMAL(9,6), p_lon2 DECIMAL(9,6)
)
RETURNS DECIMAL(10,3)
DETERMINISTIC
NO SQL
BEGIN
    RETURN ROUND(
        ST_Distance_Sphere(POINT(p_lon1, p_lat1), POINT(p_lon2, p_lat2)) / 1000,
        3
    );
END$$

-- ============================================================================
-- 7. VIEWS OBRIGATORIAS
-- ============================================================================

CREATE OR REPLACE VIEW vw_pedido_totais AS
SELECT
    p.id_pedido,
    p.id_cliente,
    p.id_restaurante,
    p.data_pedido,
    p.situacao,
    COALESCE(i.subtotal, 0.00) AS subtotal,
    p.taxa_entrega,
    p.valor_desconto,
    ROUND(COALESCE(i.subtotal, 0.00) + p.taxa_entrega - p.valor_desconto, 2) AS valor_total,
    p.percentual_comissao_aplicado,
    ROUND(COALESCE(i.subtotal, 0.00) * p.percentual_comissao_aplicado / 100, 2) AS valor_comissao
FROM pedido p
LEFT JOIN (
    SELECT id_pedido, SUM(quantidade * preco_unitario_venda) AS subtotal
    FROM item_pedido
    GROUP BY id_pedido
) i ON i.id_pedido = p.id_pedido$$

CREATE OR REPLACE VIEW vw_comprovante_pedido AS
SELECT
    p.id_pedido,
    p.data_pedido,
    p.situacao,
    c.id_cliente,
    c.nome AS nome_cliente,
    r.id_restaurante,
    r.nome_fantasia AS restaurante,
    pr.id_produto,
    pr.nome AS produto,
    ip.quantidade,
    ip.preco_unitario_venda,
    ROUND(ip.quantidade * ip.preco_unitario_venda, 2) AS subtotal_item,
    ip.observacao,
    v.subtotal,
    p.taxa_entrega,
    p.valor_desconto,
    v.valor_total
FROM pedido p
JOIN cliente c ON c.id_cliente = p.id_cliente
JOIN restaurante r ON r.id_restaurante = p.id_restaurante
JOIN item_pedido ip ON ip.id_pedido = p.id_pedido
JOIN produto pr ON pr.id_produto = ip.id_produto
JOIN vw_pedido_totais v ON v.id_pedido = p.id_pedido$$

CREATE OR REPLACE VIEW vw_conferencia_pagamento AS
SELECT
    v.id_pedido,
    v.valor_total,
    COALESCE(SUM(CASE WHEN pg.situacao = 'APROVADO' THEN pg.valor ELSE 0 END), 0.00) AS total_aprovado,
    COALESCE(SUM(CASE WHEN pg.situacao = 'PENDENTE' THEN pg.valor ELSE 0 END), 0.00) AS total_pendente,
    COALESCE(SUM(CASE WHEN pg.situacao IN ('APROVADO','PENDENTE') THEN pg.valor ELSE 0 END), 0.00) AS total_aprovado_mais_pendente,
    COALESCE(SUM(CASE WHEN fp.exige_pagamento_online = 0 THEN 1 ELSE 0 END), 0) AS quantidade_pagamentos_na_entrega,
    CASE
      WHEN COALESCE(SUM(CASE WHEN fp.exige_pagamento_online = 0 THEN 1 ELSE 0 END), 0) > 0
       AND COALESCE(SUM(CASE WHEN pg.situacao IN ('APROVADO','PENDENTE') THEN pg.valor ELSE 0 END), 0.00) = v.valor_total
        THEN 'COMPATIVEL_PENDENTE_OU_APROVADO'
      WHEN COALESCE(SUM(CASE WHEN fp.exige_pagamento_online = 1 AND pg.situacao = 'APROVADO' THEN pg.valor ELSE 0 END), 0.00) = v.valor_total
        THEN 'APROVADO'
      ELSE 'DIVERGENTE'
    END AS resultado_conferencia
FROM vw_pedido_totais v
LEFT JOIN pagamento pg ON pg.id_pedido = v.id_pedido
LEFT JOIN forma_pagamento fp ON fp.id_forma_pagamento = pg.id_forma_pagamento
GROUP BY v.id_pedido, v.valor_total$$

CREATE OR REPLACE VIEW vw_media_avaliacao AS
SELECT
    'RESTAURANTE' AS tipo_avaliado,
    p.id_restaurante AS id_avaliado,
    ROUND(AVG(a.nota_restaurante), 2) AS media_avaliacao,
    COUNT(*) AS quantidade_avaliacoes
FROM avaliacao a
JOIN pedido p ON p.id_pedido = a.id_pedido
GROUP BY p.id_restaurante
UNION ALL
SELECT
    'ENTREGADOR' AS tipo_avaliado,
    e.id_entregador AS id_avaliado,
    ROUND(AVG(a.nota_entrega), 2) AS media_avaliacao,
    COUNT(*) AS quantidade_avaliacoes
FROM avaliacao a
JOIN entrega e ON e.id_pedido = a.id_pedido
GROUP BY e.id_entregador$$

CREATE OR REPLACE VIEW vw_repasse_restaurante AS
SELECT
    v.id_restaurante,
    DATE(v.data_pedido) AS data_referencia,
    COUNT(*) AS quantidade_pedidos,
    ROUND(SUM(v.subtotal), 2) AS total_subtotal,
    ROUND(SUM(v.valor_comissao), 2) AS total_comissao,
    ROUND(SUM(COALESCE(est.total_estornado, 0.00)), 2) AS total_estornos_concluidos,
    ROUND(SUM(v.subtotal - v.valor_comissao - COALESCE(est.total_estornado, 0.00)), 2) AS valor_repasse
FROM vw_pedido_totais v
LEFT JOIN (
    SELECT pg.id_pedido, SUM(es.valor) AS total_estornado
    FROM pagamento pg
    JOIN estorno es ON es.id_pagamento = pg.id_pagamento
    WHERE es.situacao = 'CONCLUIDO'
    GROUP BY pg.id_pedido
) est ON est.id_pedido = v.id_pedido
WHERE v.situacao <> 'CANCELADO'
GROUP BY v.id_restaurante, DATE(v.data_pedido)$$

-- ============================================================================
-- 8. PROCEDURE DE AUDITORIA
-- A aplicacao configura as variaveis de sessao do ator e do IP antes das DML.
-- ============================================================================

CREATE PROCEDURE sp_registrar_auditoria(
    IN p_operacao VARCHAR(20),
    IN p_tabela VARCHAR(64),
    IN p_id_registro BIGINT UNSIGNED,
    IN p_valor_anterior JSON,
    IN p_valor_novo JSON
)
SQL SECURITY DEFINER
MODIFIES SQL DATA
BEGIN
    DECLARE v_id_usuario INT UNSIGNED DEFAULT NULL;
    DECLARE v_id_cliente INT UNSIGNED DEFAULT NULL;
    DECLARE v_id_entregador INT UNSIGNED DEFAULT NULL;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        SET @permitir_log_auditoria = NULL;
        RESIGNAL;
    END;

    SET v_id_usuario = @app_id_usuario;
    SET v_id_cliente = @app_id_cliente;
    SET v_id_entregador = @app_id_entregador;

    IF (v_id_usuario IS NOT NULL) + (v_id_cliente IS NOT NULL) + (v_id_entregador IS NOT NULL) > 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Defina apenas um ator de auditoria por sessao';
    END IF;

    SET @permitir_log_auditoria = 1;
    INSERT INTO log_auditoria (
        id_usuario, id_cliente, id_entregador, operacao, tabela_afetada,
        id_registro_afetado, valor_anterior, valor_novo, data_evento, ip_origem
    ) VALUES (
        v_id_usuario, v_id_cliente, v_id_entregador, p_operacao, p_tabela,
        p_id_registro, p_valor_anterior, p_valor_novo, CURRENT_TIMESTAMP,
        COALESCE(@app_ip_origem, 'NAO_INFORMADO')
    );
    SET @permitir_log_auditoria = NULL;
END$$

-- ============================================================================
-- 9. PROCEDURE TRANSACIONAL DE CONFIRMACAO DO PEDIDO
-- Fluxo: START TRANSACTION; inserir pedido/itens/pagamentos; chamar a procedure; COMMIT.
-- Em SQLEXCEPTION, a procedure executa ROLLBACK e propaga o erro.
-- ============================================================================

CREATE PROCEDURE sp_confirmar_pedido(IN p_id_pedido INT UNSIGNED)
SQL SECURITY DEFINER
MODIFIES SQL DATA
main: BEGIN
    DECLARE v_id_cliente INT UNSIGNED;
    DECLARE v_id_restaurante INT UNSIGNED;
    DECLARE v_id_endereco INT UNSIGNED;
    DECLARE v_id_cupom INT UNSIGNED;
    DECLARE v_situacao_pedido VARCHAR(20);
    DECLARE v_cliente_ativo TINYINT UNSIGNED;
    DECLARE v_data_revogacao DATETIME;
    DECLARE v_data_nascimento DATE;
    DECLARE v_restaurante_ativo TINYINT UNSIGNED;
    DECLARE v_restaurante_situacao VARCHAR(20);
    DECLARE v_valor_minimo DECIMAL(10,2);
    DECLARE v_raio DECIMAL(8,2);
    DECLARE v_taxa_base DECIMAL(10,2);
    DECLARE v_taxa_km DECIMAL(10,2);
    DECLARE v_comissao DECIMAL(5,2);
    DECLARE v_lat_rest DECIMAL(9,6);
    DECLARE v_lon_rest DECIMAL(9,6);
    DECLARE v_lat_end DECIMAL(9,6);
    DECLARE v_lon_end DECIMAL(9,6);
    DECLARE v_distancia DECIMAL(10,3);
    DECLARE v_subtotal DECIMAL(12,2) DEFAULT 0.00;
    DECLARE v_taxa DECIMAL(10,2) DEFAULT 0.00;
    DECLARE v_desconto DECIMAL(10,2) DEFAULT 0.00;
    DECLARE v_total DECIMAL(12,2) DEFAULT 0.00;
    DECLARE v_tipo_desconto VARCHAR(20);
    DECLARE v_valor_beneficio DECIMAL(10,2);
    DECLARE v_minimo_cupom DECIMAL(10,2);
    DECLARE v_inicio_cupom DATETIME;
    DECLARE v_fim_cupom DATETIME;
    DECLARE v_limite_cupom INT UNSIGNED;
    DECLARE v_cupom_ativo TINYINT UNSIGNED;
    DECLARE v_usos_cupom INT UNSIGNED DEFAULT 0;
    DECLARE v_total_aprovado DECIMAL(12,2) DEFAULT 0.00;
    DECLARE v_total_pendente DECIMAL(12,2) DEFAULT 0.00;
    DECLARE v_pagamentos_offline INT DEFAULT 0;
    DECLARE v_tem_alcool TINYINT DEFAULT 0;
    DECLARE v_hora_ok INT DEFAULT 0;
    DECLARE v_total_pagamentos INT DEFAULT 0;
    DECLARE v_itens_invalidos INT DEFAULT 0;
    DECLARE v_id_pagamento_bloqueado INT UNSIGNED DEFAULT NULL;
    DECLARE v_ultimo_pagamento INT UNSIGNED DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        SET @permitir_confirmacao = NULL;
        ROLLBACK;
        RESIGNAL;
    END;

    IF @@in_transaction = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Inicie uma transacao antes de criar e confirmar o pedido';
    END IF;

    SELECT id_cliente, id_restaurante, id_endereco_cliente, id_cupom, situacao
      INTO v_id_cliente, v_id_restaurante, v_id_endereco, v_id_cupom, v_situacao_pedido
    FROM pedido
    WHERE id_pedido = p_id_pedido
    FOR UPDATE;

    IF v_id_cliente IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Pedido nao encontrado';
    END IF;
    IF @app_id_cliente IS NOT NULL AND @app_id_cliente <> v_id_cliente THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cliente autenticado so pode confirmar pedido proprio';
    END IF;
    IF v_situacao_pedido <> 'CRIADO' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Somente pedidos em CRIADO podem ser confirmados';
    END IF;

    SELECT ativo, data_revogacao_consentimento, data_nascimento
      INTO v_cliente_ativo, v_data_revogacao, v_data_nascimento
    FROM cliente
    WHERE id_cliente = v_id_cliente
    FOR UPDATE;

    IF v_cliente_ativo <> 1 OR v_data_revogacao IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cliente inativo ou com consentimento revogado';
    END IF;

    SELECT ativo, situacao, valor_pedido_minimo, raio_entrega_km,
           taxa_entrega_base, taxa_entrega_por_km, percentual_comissao,
           latitude, longitude
      INTO v_restaurante_ativo, v_restaurante_situacao, v_valor_minimo, v_raio,
           v_taxa_base, v_taxa_km, v_comissao, v_lat_rest, v_lon_rest
    FROM restaurante
    WHERE id_restaurante = v_id_restaurante
    FOR UPDATE;

    IF v_restaurante_ativo <> 1 OR v_restaurante_situacao <> 'ABERTO' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Restaurante inativo, suspenso ou fechado';
    END IF;

    SELECT latitude, longitude
      INTO v_lat_end, v_lon_end
    FROM endereco_cliente
    WHERE id_endereco_cliente = v_id_endereco AND id_cliente = v_id_cliente AND ativo = 1
    FOR UPDATE;

    SET v_distancia = fn_distancia_km(v_lat_rest, v_lon_rest, v_lat_end, v_lon_end);
    IF v_distancia IS NULL OR v_distancia > v_raio THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Endereco fora da area de entrega do restaurante';
    END IF;

    SELECT COUNT(*) INTO v_hora_ok
    FROM horario_funcionamento
    WHERE id_restaurante = v_id_restaurante
      AND dia_semana = WEEKDAY(CURRENT_TIMESTAMP) + 1
      AND CURTIME() >= hora_abertura
      AND CURTIME() < hora_fechamento;
    IF v_hora_ok = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Restaurante fora do horario de funcionamento';
    END IF;

    SELECT COALESCE(SUM(quantidade * preco_unitario_venda), 0.00)
      INTO v_subtotal
    FROM item_pedido
    WHERE id_pedido = p_id_pedido;
    IF v_subtotal <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Pedido precisa conter ao menos um item';
    END IF;
    IF v_subtotal < v_valor_minimo THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Subtotal inferior ao pedido minimo do restaurante';
    END IF;

    SELECT COUNT(*) INTO v_itens_invalidos
    FROM item_pedido ip
    JOIN produto pr ON pr.id_produto = ip.id_produto
    WHERE ip.id_pedido = p_id_pedido
      AND (pr.id_restaurante <> v_id_restaurante OR pr.ativo <> 1 OR pr.disponivel <> 1);
    IF v_itens_invalidos > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Pedido contem produto de outro restaurante, inativo ou indisponivel';
    END IF;

    SELECT EXISTS(
        SELECT 1 FROM item_pedido ip
        JOIN produto pr ON pr.id_produto = ip.id_produto
        WHERE ip.id_pedido = p_id_pedido AND pr.alcoolico = 1
    ) INTO v_tem_alcool;
    IF v_tem_alcool = 1 AND (v_data_nascimento IS NULL OR TIMESTAMPDIFF(YEAR, v_data_nascimento, CURDATE()) < 18) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Pedido com bebida alcoolica exige cliente maior de 18 anos';
    END IF;

    SET v_taxa = ROUND(v_taxa_base + (v_taxa_km * v_distancia), 2);

    IF v_id_cupom IS NOT NULL THEN
        SELECT tipo_desconto, valor_beneficio, valor_pedido_minimo,
               data_inicio, data_fim, limite_uso_por_cliente, ativo
          INTO v_tipo_desconto, v_valor_beneficio, v_minimo_cupom,
               v_inicio_cupom, v_fim_cupom, v_limite_cupom, v_cupom_ativo
        FROM cupom
        WHERE id_cupom = v_id_cupom
        FOR UPDATE;

        IF v_cupom_ativo <> 1 OR CURRENT_TIMESTAMP NOT BETWEEN v_inicio_cupom AND v_fim_cupom THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cupom inativo ou fora do periodo de vigencia';
        END IF;
        IF v_subtotal < v_minimo_cupom THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Subtotal nao atinge o minimo exigido pelo cupom';
        END IF;

        SELECT COUNT(*) INTO v_usos_cupom
        FROM pedido
        WHERE id_cliente = v_id_cliente
          AND id_cupom = v_id_cupom
          AND situacao <> 'CANCELADO'
          AND id_pedido <> p_id_pedido;
        IF v_usos_cupom >= v_limite_cupom THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Limite de uso do cupom atingido para este cliente';
        END IF;

        SET v_desconto = CASE
            WHEN v_tipo_desconto = 'PERCENTUAL' THEN ROUND(v_subtotal * v_valor_beneficio / 100, 2)
            ELSE v_valor_beneficio
        END;
        SET v_desconto = LEAST(v_desconto, v_subtotal);
    ELSE
        SET v_desconto = 0.00;
    END IF;

    SET v_total = ROUND(v_subtotal + v_taxa - v_desconto, 2);

    -- Bloqueia cada pagamento existente com leitura bloqueante real (FOR UPDATE).
    -- A busca incremental evita depender de cursor materializado para reter locks.
    SET v_ultimo_pagamento = 0;
    bloqueia_pagamentos: LOOP
        SET v_id_pagamento_bloqueado = NULL;
        BEGIN
            DECLARE CONTINUE HANDLER FOR NOT FOUND
                SET v_id_pagamento_bloqueado = NULL;
            SELECT pg.id_pagamento
              INTO v_id_pagamento_bloqueado
            FROM pagamento pg
            WHERE pg.id_pedido = p_id_pedido
              AND pg.id_pagamento > v_ultimo_pagamento
            ORDER BY pg.id_pagamento
            LIMIT 1
            FOR UPDATE;
        END;

        IF v_id_pagamento_bloqueado IS NULL THEN
            LEAVE bloqueia_pagamentos;
        END IF;
        SET v_ultimo_pagamento = v_id_pagamento_bloqueado;
    END LOOP;

    SELECT COUNT(*),
           COALESCE(SUM(CASE WHEN pg.situacao = 'APROVADO' THEN pg.valor ELSE 0 END), 0.00),
           COALESCE(SUM(CASE WHEN pg.situacao = 'PENDENTE' THEN pg.valor ELSE 0 END), 0.00),
           COALESCE(SUM(CASE WHEN fp.exige_pagamento_online = 0 THEN 1 ELSE 0 END), 0)
      INTO v_total_pagamentos, v_total_aprovado, v_total_pendente, v_pagamentos_offline
    FROM pagamento pg
    JOIN forma_pagamento fp ON fp.id_forma_pagamento = pg.id_forma_pagamento
    WHERE pg.id_pedido = p_id_pedido;

    IF v_total_pagamentos = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Pedido precisa ter ao menos um registro de pagamento';
    END IF;
    IF v_pagamentos_offline > 0 THEN
        IF ROUND(v_total_aprovado + v_total_pendente, 2) <> v_total THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Pagamentos aprovados e pendentes devem totalizar o pedido';
        END IF;
    ELSE
        IF ROUND(v_total_aprovado, 2) <> v_total THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Pagamentos online aprovados devem totalizar o pedido';
        END IF;
    END IF;

    SET @permitir_confirmacao = 1;
    UPDATE pedido
       SET situacao = 'CONFIRMADO',
           taxa_entrega = v_taxa,
           valor_desconto = v_desconto,
           percentual_comissao_aplicado = v_comissao
     WHERE id_pedido = p_id_pedido;
    SET @permitir_confirmacao = NULL;
END$$

-- Atualizacao de estado da entrega com recalculo transacional do entregador.
-- Executar para COLETADA, CONCLUIDA ou CANCELADA.
CREATE PROCEDURE sp_atualizar_entrega(
    IN p_id_entrega INT UNSIGNED,
    IN p_nova_situacao VARCHAR(20),
    IN p_distancia_km DECIMAL(8,2),
    IN p_maioridade_conferida TINYINT UNSIGNED
)
SQL SECURITY DEFINER
MODIFIES SQL DATA
BEGIN
    DECLARE v_id_entregador INT UNSIGNED;
    DECLARE v_entregas_abertas INT DEFAULT 0;
    DECLARE v_ativo TINYINT UNSIGNED;
    DECLARE v_situacao_entregador VARCHAR(20);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        SET @permitir_atualizacao_entrega = NULL;
        SET @permitir_entrega = NULL;
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_nova_situacao NOT IN ('COLETADA','CONCLUIDA','CANCELADA') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Situacao solicitada para entrega invalida';
    END IF;

    START TRANSACTION;
    SELECT id_entregador INTO v_id_entregador
    FROM entrega WHERE id_entrega = p_id_entrega FOR UPDATE;
    IF v_id_entregador IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Entrega nao encontrada';
    END IF;

    SET @permitir_atualizacao_entrega = 1;
    UPDATE entrega
       SET situacao = p_nova_situacao,
           distancia_km = COALESCE(p_distancia_km, distancia_km),
           maioridade_conferida = COALESCE(p_maioridade_conferida, maioridade_conferida)
     WHERE id_entrega = p_id_entrega;
    SET @permitir_atualizacao_entrega = NULL;
    SET @permitir_entrega = NULL;

    SELECT COUNT(*) INTO v_entregas_abertas
    FROM entrega
    WHERE id_entregador = v_id_entregador AND situacao IN ('ATRIBUIDA','COLETADA');
    SELECT ativo, situacao INTO v_ativo, v_situacao_entregador
    FROM entregador WHERE id_entregador = v_id_entregador FOR UPDATE;

    UPDATE entregador
       SET situacao = CASE
           WHEN v_ativo = 0 OR v_situacao_entregador = 'BLOQUEADO' THEN 'BLOQUEADO'
           WHEN v_entregas_abertas > 0 THEN 'EM_ENTREGA'
           ELSE 'DISPONIVEL' END
     WHERE id_entregador = v_id_entregador;

    COMMIT;
END$$

-- Solicita estorno por direito de arrependimento para pedido ja entregue.
-- A data limite e calculada a partir de entrega.data_entrega (7 dias).
CREATE PROCEDURE sp_solicitar_estorno(
    IN p_id_pagamento INT UNSIGNED,
    IN p_id_usuario INT UNSIGNED,
    IN p_valor DECIMAL(10,2),
    IN p_motivo VARCHAR(255)
)
SQL SECURITY DEFINER
MODIFIES SQL DATA
BEGIN
    DECLARE v_id_pedido INT UNSIGNED;
    DECLARE v_situacao_pedido VARCHAR(20);
    DECLARE v_data_entrega DATETIME;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        SET @permitir_estorno = NULL;
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;
    SELECT id_pedido INTO v_id_pedido
    FROM pagamento WHERE id_pagamento = p_id_pagamento FOR UPDATE;
    IF v_id_pedido IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Pagamento nao encontrado';
    END IF;

    SELECT situacao INTO v_situacao_pedido
    FROM pedido WHERE id_pedido = v_id_pedido;
    IF v_situacao_pedido <> 'ENTREGUE' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Estorno por arrependimento aplica-se a pedido ENTREGUE';
    END IF;

    SELECT data_entrega INTO v_data_entrega
    FROM entrega WHERE id_pedido = v_id_pedido;
    IF v_data_entrega IS NULL OR CURRENT_TIMESTAMP > v_data_entrega + INTERVAL 7 DAY THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Prazo de 7 dias para arrependimento expirado';
    END IF;

    SET @permitir_estorno = 1;
    INSERT INTO estorno (id_pagamento, id_usuario, valor, motivo, situacao, data_solicitacao)
    VALUES (p_id_pagamento, p_id_usuario, p_valor, p_motivo, 'SOLICITADO', CURRENT_TIMESTAMP);
    SET @permitir_estorno = NULL;

    COMMIT;
END$$

-- ============================================================================
-- 10. PROCEDURE DE ANONIMIZACAO E EVENTO DE RETENCAO
-- p_tipo_titular: 'CLIENTE' ou 'ENTREGADOR'
-- ============================================================================

CREATE PROCEDURE sp_anonimizar_titular(
    IN p_tipo_titular VARCHAR(20),
    IN p_id_titular INT UNSIGNED
)
SQL SECURITY DEFINER
MODIFIES SQL DATA
BEGIN
    DECLARE v_ativo INT DEFAULT 0;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    IF p_tipo_titular = 'CLIENTE' THEN
        SELECT ativo INTO v_ativo FROM cliente WHERE id_cliente = p_id_titular FOR UPDATE;
        IF v_ativo = 0 THEN
            -- Permite anonimizar titular previamente inativo, desde que ainda nao anonimizado.
            IF EXISTS (SELECT 1 FROM cliente WHERE id_cliente = p_id_titular AND data_anonimizacao IS NOT NULL) THEN
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cliente ja foi anonimizado';
            END IF;
        END IF;

        UPDATE endereco_cliente
           SET apelido = 'ANONIMIZADO',
               logradouro = 'ANONIMIZADO',
               numero = '0',
               complemento = NULL,
               bairro = 'ANONIMIZADO',
               cep = '00000000',
               latitude = 0.000000,
               longitude = 0.000000,
               principal = 0,
               ativo = 0
         WHERE id_cliente = p_id_titular;

        UPDATE cliente
           SET nome = 'TITULAR ANONIMIZADO',
               cpf_hash = SHA2(CONCAT(UUID(), RAND(), id_cliente), 256),
               cpf_cifrado = NULL,
               email = NULL,
               telefone_cifrado = NULL,
               data_nascimento = NULL,
               senha_hash = SHA2(CONCAT(UUID(), RAND()), 256),
               data_anonimizacao = CURRENT_TIMESTAMP,
               ativo = 0
         WHERE id_cliente = p_id_titular AND data_anonimizacao IS NULL;

        IF ROW_COUNT() = 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cliente nao encontrado ou ja anonimizado';
        END IF;

    ELSEIF p_tipo_titular = 'ENTREGADOR' THEN
        SELECT ativo INTO v_ativo FROM entregador WHERE id_entregador = p_id_titular FOR UPDATE;
        IF EXISTS (
            SELECT 1 FROM entrega
            WHERE id_entregador = p_id_titular AND situacao IN ('ATRIBUIDA','COLETADA')
        ) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Entregador possui entrega em aberto';
        END IF;

        UPDATE entregador
           SET nome = 'TITULAR ANONIMIZADO',
               cpf_hash = SHA2(CONCAT(UUID(), RAND(), id_entregador), 256),
               cpf_cifrado = NULL,
               telefone_cifrado = NULL,
               senha_hash = SHA2(CONCAT(UUID(), RAND()), 256),
               data_anonimizacao = CURRENT_TIMESTAMP,
               ativo = 0,
               situacao = 'BLOQUEADO'
         WHERE id_entregador = p_id_titular AND data_anonimizacao IS NULL;

        IF ROW_COUNT() = 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Entregador nao encontrado ou ja anonimizado';
        END IF;
    ELSE
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Tipo de titular deve ser CLIENTE ou ENTREGADOR';
    END IF;

    COMMIT;
END$$

CREATE PROCEDURE sp_processar_anonimizacao_vencida()
SQL SECURITY DEFINER
MODIFIES SQL DATA
BEGIN
    DECLARE v_fim INT DEFAULT 0;
    DECLARE v_id_cliente INT UNSIGNED;
    DECLARE v_id_entregador INT UNSIGNED;
    DECLARE cur_clientes CURSOR FOR
        SELECT c.id_cliente
        FROM cliente c
        JOIN (
            SELECT id_cliente, MAX(data_pedido) AS ultima_compra
            FROM pedido
            GROUP BY id_cliente
        ) p ON p.id_cliente = c.id_cliente
        WHERE c.data_anonimizacao IS NULL
          AND p.ultima_compra <= CURRENT_TIMESTAMP - INTERVAL 5 YEAR;
    DECLARE cur_entregadores CURSOR FOR
        SELECT d.id_entregador
        FROM entregador d
        JOIN (
            SELECT id_entregador, MAX(data_entrega) AS ultima_entrega
            FROM entrega
            WHERE data_entrega IS NOT NULL
            GROUP BY id_entregador
        ) e ON e.id_entregador = d.id_entregador
        WHERE d.data_anonimizacao IS NULL
          AND e.ultima_entrega <= CURRENT_TIMESTAMP - INTERVAL 5 YEAR;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_fim = 1;

    OPEN cur_clientes;
    loop_clientes: LOOP
        FETCH cur_clientes INTO v_id_cliente;
        IF v_fim = 1 THEN
            LEAVE loop_clientes;
        END IF;
        CALL sp_anonimizar_titular('CLIENTE', v_id_cliente);
    END LOOP;
    CLOSE cur_clientes;

    SET v_fim = 0;
    OPEN cur_entregadores;
    loop_entregadores: LOOP
        FETCH cur_entregadores INTO v_id_entregador;
        IF v_fim = 1 THEN
            LEAVE loop_entregadores;
        END IF;
        CALL sp_anonimizar_titular('ENTREGADOR', v_id_entregador);
    END LOOP;
    CLOSE cur_entregadores;
END$$

-- Evento diario. Para executa-lo automaticamente, o administrador deve habilitar
-- event_scheduler=ON no servidor MySQL.
CREATE EVENT IF NOT EXISTS ev_anonimizacao_diaria
ON SCHEDULE EVERY 1 DAY
STARTS (CURRENT_TIMESTAMP + INTERVAL 1 DAY)
ON COMPLETION PRESERVE
ENABLE
DO CALL sp_processar_anonimizacao_vencida()$$

-- ============================================================================
-- 11. TRIGGERS DE VALIDACAO E CICLO DE VIDA
-- ============================================================================

CREATE TRIGGER trg_restaurante_bi
BEFORE INSERT ON restaurante
FOR EACH ROW
BEGIN
    IF fn_valida_cnpj(NEW.cnpj) <> 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CNPJ invalido';
    END IF;
END$$

CREATE TRIGGER trg_restaurante_bu
BEFORE UPDATE ON restaurante
FOR EACH ROW
BEGIN
    IF fn_valida_cnpj(NEW.cnpj) <> 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CNPJ invalido';
    END IF;
END$$

CREATE TRIGGER trg_pedido_bi
BEFORE INSERT ON pedido
FOR EACH ROW
BEGIN
    DECLARE v_cliente_ativo TINYINT;
    DECLARE v_revogacao DATETIME;
    DECLARE v_restaurante_ativo TINYINT;
    DECLARE v_restaurante_situacao VARCHAR(20);

    IF @app_id_cliente IS NOT NULL AND @app_id_cliente <> NEW.id_cliente THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cliente autenticado so pode criar pedido proprio';
    END IF;

    SELECT ativo, data_revogacao_consentimento
      INTO v_cliente_ativo, v_revogacao
    FROM cliente WHERE id_cliente = NEW.id_cliente;
    IF v_cliente_ativo <> 1 OR v_revogacao IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Nao e permitido criar pedido para cliente inativo ou com consentimento revogado';
    END IF;

    SELECT ativo, situacao
      INTO v_restaurante_ativo, v_restaurante_situacao
    FROM restaurante WHERE id_restaurante = NEW.id_restaurante;
    IF v_restaurante_ativo <> 1 OR v_restaurante_situacao = 'SUSPENSO' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Nao e permitido criar pedido para restaurante inativo ou suspenso';
    END IF;

    SET NEW.data_pedido = CURRENT_TIMESTAMP;
    SET NEW.situacao = 'CRIADO';
END$$

CREATE TRIGGER trg_pedido_bu
BEFORE UPDATE ON pedido
FOR EACH ROW
BEGIN
    DECLARE v_perfil_cancelamento VARCHAR(20);
    DECLARE v_restaurante_usuario_cancelamento INT UNSIGNED;
    DECLARE v_usuario_cancelamento_ativo TINYINT UNSIGNED;

    IF OLD.situacao IN ('ENTREGUE','CANCELADO') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Pedido encerrado e imutavel';
    END IF;

    IF NEW.situacao <> OLD.situacao THEN
        IF NOT (
            (OLD.situacao = 'CRIADO' AND NEW.situacao IN ('CONFIRMADO','CANCELADO')) OR
            (OLD.situacao = 'CONFIRMADO' AND NEW.situacao IN ('EM_PREPARO','CANCELADO')) OR
            (OLD.situacao = 'EM_PREPARO' AND NEW.situacao IN ('PRONTO','CANCELADO')) OR
            (OLD.situacao = 'PRONTO' AND NEW.situacao IN ('EM_ROTA','CANCELADO')) OR
            (OLD.situacao = 'EM_ROTA' AND NEW.situacao IN ('ENTREGUE','CANCELADO'))
        ) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Transicao de situacao do pedido nao permitida';
        END IF;
    END IF;

    IF NEW.situacao = 'CONFIRMADO' AND OLD.situacao <> 'CONFIRMADO'
       AND COALESCE(@permitir_confirmacao, 0) <> 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Use CALL sp_confirmar_pedido(id) para confirmar o pedido';
    END IF;

    IF OLD.situacao <> 'CRIADO' AND (
        NOT (NEW.id_cliente <=> OLD.id_cliente) OR
        NOT (NEW.id_restaurante <=> OLD.id_restaurante) OR
        NOT (NEW.id_endereco_cliente <=> OLD.id_endereco_cliente) OR
        NOT (NEW.id_cupom <=> OLD.id_cupom) OR
        NOT (NEW.taxa_entrega <=> OLD.taxa_entrega) OR
        NOT (NEW.valor_desconto <=> OLD.valor_desconto) OR
        NOT (NEW.percentual_comissao_aplicado <=> OLD.percentual_comissao_aplicado)
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Dados e valores do pedido sao congelados apos a confirmacao';
    END IF;

    IF NEW.situacao = 'EM_ROTA' AND OLD.situacao <> 'EM_ROTA'
       AND COALESCE(@permitir_inicio_entrega, 0) <> 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Pedido so pode entrar em EM_ROTA apos atribuicao de entrega';
    END IF;

    IF NEW.situacao = 'ENTREGUE' AND OLD.situacao <> 'ENTREGUE'
       AND COALESCE(@permitir_entrega, 0) <> 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A conclusao do pedido deve ocorrer pela rotina de entrega';
    END IF;

    IF NEW.situacao = 'CANCELADO' AND OLD.situacao <> 'CANCELADO' THEN
        IF NEW.origem_cancelamento IS NULL OR NEW.motivo_cancelamento IS NULL OR TRIM(NEW.motivo_cancelamento) = '' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cancelamento exige origem e motivo';
        END IF;
        IF NEW.origem_cancelamento = 'CLIENTE' THEN
            IF @app_id_cliente IS NULL OR @app_id_cliente <> OLD.id_cliente THEN
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cliente so pode cancelar o proprio pedido';
            END IF;
        ELSEIF NEW.origem_cancelamento = 'RESTAURANTE' THEN
            IF @app_id_usuario IS NULL THEN
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cancelamento pelo restaurante exige usuario autenticado';
            END IF;
            SELECT perfil, id_restaurante, ativo
              INTO v_perfil_cancelamento, v_restaurante_usuario_cancelamento, v_usuario_cancelamento_ativo
            FROM usuario WHERE id_usuario = @app_id_usuario;
            IF v_usuario_cancelamento_ativo <> 1 OR v_perfil_cancelamento <> 'RESTAURANTE'
               OR v_restaurante_usuario_cancelamento <> OLD.id_restaurante THEN
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Restaurante so pode cancelar pedido do proprio estabelecimento';
            END IF;
        ELSEIF NEW.origem_cancelamento = 'SUPORTE' THEN
            IF NEW.id_usuario_cancelamento IS NULL OR NEW.id_usuario_cancelamento <> @app_id_usuario THEN
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cancelamento por suporte exige o usuario autenticado responsavel';
            END IF;
            SELECT perfil, ativo INTO v_perfil_cancelamento, v_usuario_cancelamento_ativo
            FROM usuario WHERE id_usuario = NEW.id_usuario_cancelamento;
            IF v_usuario_cancelamento_ativo <> 1 OR v_perfil_cancelamento <> 'SUPORTE' THEN
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cancelamento por suporte exige perfil SUPORTE ativo';
            END IF;
        ELSEIF NEW.origem_cancelamento = 'SISTEMA' THEN
            IF @app_id_usuario IS NULL THEN
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cancelamento de sistema exige usuario de servico';
            END IF;
            SELECT perfil, ativo INTO v_perfil_cancelamento, v_usuario_cancelamento_ativo
            FROM usuario WHERE id_usuario = @app_id_usuario;
            IF v_usuario_cancelamento_ativo <> 1 OR v_perfil_cancelamento <> 'ADMINISTRADOR' THEN
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cancelamento de sistema exige usuario ADMINISTRADOR ativo';
            END IF;
            SET NEW.id_usuario_cancelamento = @app_id_usuario;
        END IF;
        SET NEW.data_cancelamento = CURRENT_TIMESTAMP;
    END IF;

    IF NOT (NEW.data_pedido <=> OLD.data_pedido) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'data_pedido e gerada pelo servidor e nao pode ser alterada';
    END IF;
    IF NEW.situacao <> 'CANCELADO' AND NEW.data_cancelamento IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'data_cancelamento so pode ser preenchida no cancelamento';
    END IF;
END$$

CREATE TRIGGER trg_pedido_ai
AFTER INSERT ON pedido
FOR EACH ROW
BEGIN
    SET @permitir_historico_status = 1;
    INSERT INTO historico_status_pedido (
        id_pedido, id_usuario, situacao_anterior, situacao_nova, data_mudanca
    ) VALUES (
        NEW.id_pedido, @app_id_usuario, NULL, NEW.situacao, CURRENT_TIMESTAMP
    );
    SET @permitir_historico_status = NULL;
END$$

CREATE TRIGGER trg_pedido_au
AFTER UPDATE ON pedido
FOR EACH ROW
BEGIN
    DECLARE v_id_entregador INT UNSIGNED DEFAULT NULL;
    DECLARE v_entregas_abertas INT DEFAULT 0;

    IF NEW.situacao <> OLD.situacao THEN
        SET @permitir_historico_status = 1;
        INSERT INTO historico_status_pedido (
            id_pedido, id_usuario, situacao_anterior, situacao_nova, data_mudanca
        ) VALUES (
            NEW.id_pedido, @app_id_usuario, OLD.situacao, NEW.situacao, CURRENT_TIMESTAMP
        );
        SET @permitir_historico_status = NULL;

        IF NEW.situacao = 'ENTREGUE' THEN
            UPDATE pagamento
               SET situacao = 'APROVADO'
             WHERE id_pedido = NEW.id_pedido AND situacao = 'PENDENTE'
               AND id_forma_pagamento IN (
                   SELECT id_forma_pagamento FROM forma_pagamento WHERE exige_pagamento_online = 0
               );
        END IF;

        IF NEW.situacao = 'CANCELADO' THEN
            SET @permitir_estorno = 1;
            IF OLD.situacao IN ('CRIADO','CONFIRMADO') THEN
                INSERT INTO estorno (id_pagamento, id_usuario, valor, motivo, situacao, data_solicitacao)
                SELECT pg.id_pagamento, @app_id_usuario, pg.valor,
                       CONCAT('Estorno integral automatico - pedido ', NEW.id_pedido),
                       'CONCLUIDO', CURRENT_TIMESTAMP
                FROM pagamento pg
                WHERE pg.id_pedido = NEW.id_pedido AND pg.situacao = 'APROVADO';
            ELSE
                INSERT INTO estorno (id_pagamento, id_usuario, valor, motivo, situacao, data_solicitacao)
                SELECT pg.id_pagamento, @app_id_usuario, pg.valor,
                       CONCAT('Solicitacao de estorno - pedido ', NEW.id_pedido),
                       'EM_ANALISE', CURRENT_TIMESTAMP
                FROM pagamento pg
                WHERE pg.id_pedido = NEW.id_pedido AND pg.situacao = 'APROVADO';
            END IF;
            SET @permitir_estorno = NULL;

            SET @permitir_atualizacao_entrega = 1;
            UPDATE entrega
               SET situacao = 'CANCELADA'
             WHERE id_pedido = NEW.id_pedido AND situacao IN ('ATRIBUIDA','COLETADA');
            SET @permitir_atualizacao_entrega = NULL;

            IF EXISTS (SELECT 1 FROM entrega WHERE id_pedido = NEW.id_pedido) THEN
                SELECT id_entregador INTO v_id_entregador
                FROM entrega WHERE id_pedido = NEW.id_pedido;
                SELECT COUNT(*) INTO v_entregas_abertas
                FROM entrega
                WHERE id_entregador = v_id_entregador AND situacao IN ('ATRIBUIDA','COLETADA');
                UPDATE entregador
                   SET situacao = CASE
                       WHEN ativo = 0 OR situacao = 'BLOQUEADO' THEN 'BLOQUEADO'
                       WHEN v_entregas_abertas > 0 THEN 'EM_ENTREGA'
                       ELSE 'DISPONIVEL' END
                 WHERE id_entregador = v_id_entregador;
            END IF;
        END IF;
    END IF;
END$$

CREATE TRIGGER trg_item_pedido_bi
BEFORE INSERT ON item_pedido
FOR EACH ROW
BEGIN
    DECLARE v_situacao_pedido VARCHAR(20);
    DECLARE v_id_restaurante_pedido INT UNSIGNED;
    DECLARE v_id_restaurante_produto INT UNSIGNED;
    DECLARE v_preco DECIMAL(10,2);
    DECLARE v_ativo TINYINT;
    DECLARE v_disponivel TINYINT;
    DECLARE v_restaurante_ativo TINYINT;
    DECLARE v_restaurante_situacao VARCHAR(20);

    SELECT situacao, id_restaurante
      INTO v_situacao_pedido, v_id_restaurante_pedido
    FROM pedido WHERE id_pedido = NEW.id_pedido;
    IF @app_id_cliente IS NOT NULL AND @app_id_cliente <> (SELECT id_cliente FROM pedido WHERE id_pedido = NEW.id_pedido) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cliente autenticado so pode incluir itens em pedido proprio';
    END IF;
    IF v_situacao_pedido <> 'CRIADO' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Itens so podem ser incluidos em pedido CRIADO';
    END IF;

    SELECT id_restaurante, preco_tabela, ativo, disponivel
      INTO v_id_restaurante_produto, v_preco, v_ativo, v_disponivel
    FROM produto WHERE id_produto = NEW.id_produto;
    IF v_id_restaurante_produto <> v_id_restaurante_pedido THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Todos os itens devem pertencer ao restaurante do pedido';
    END IF;
    IF v_ativo <> 1 OR v_disponivel <> 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Produto inativo ou indisponivel';
    END IF;

    SELECT ativo, situacao INTO v_restaurante_ativo, v_restaurante_situacao
    FROM restaurante WHERE id_restaurante = v_id_restaurante_produto;
    IF v_restaurante_ativo <> 1 OR v_restaurante_situacao <> 'ABERTO' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Produto de restaurante inativo ou fora de operacao';
    END IF;

    SET NEW.preco_unitario_venda = v_preco;
END$$

CREATE TRIGGER trg_item_pedido_bu
BEFORE UPDATE ON item_pedido
FOR EACH ROW
BEGIN
    DECLARE v_situacao_pedido VARCHAR(20);
    IF NEW.preco_unitario_venda <> OLD.preco_unitario_venda THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Preco unitario de venda e imutavel';
    END IF;
    IF NEW.id_pedido <> OLD.id_pedido OR NEW.id_produto <> OLD.id_produto THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Pedido e produto do item nao podem ser substituidos';
    END IF;
    SELECT situacao INTO v_situacao_pedido FROM pedido WHERE id_pedido = OLD.id_pedido;
    IF v_situacao_pedido <> 'CRIADO' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Itens de pedido confirmado nao podem ser alterados';
    END IF;
END$$

CREATE TRIGGER trg_item_pedido_bd
BEFORE DELETE ON item_pedido
FOR EACH ROW
BEGIN
    DECLARE v_situacao_pedido VARCHAR(20);
    SELECT situacao INTO v_situacao_pedido FROM pedido WHERE id_pedido = OLD.id_pedido;
    IF v_situacao_pedido IN ('ENTREGUE','CANCELADO') OR v_situacao_pedido <> 'CRIADO' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Itens nao podem ser excluidos apos a confirmacao';
    END IF;
END$$

CREATE TRIGGER trg_produto_bu
BEFORE UPDATE ON produto
FOR EACH ROW
BEGIN
    DECLARE v_perfil VARCHAR(20);
    DECLARE v_id_restaurante_usuario INT UNSIGNED;
    DECLARE v_usuario_ativo TINYINT;
    DECLARE v_tem_pedidos INT DEFAULT 0;

    IF NEW.id_restaurante <> OLD.id_restaurante THEN
        SELECT COUNT(*) INTO v_tem_pedidos FROM item_pedido WHERE id_produto = OLD.id_produto;
        IF v_tem_pedidos > 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Produto vinculado a pedidos nao pode trocar de restaurante';
        END IF;
    END IF;

    IF NEW.preco_tabela <> OLD.preco_tabela THEN
        IF @app_id_usuario IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Alteracao de preco exige usuario autenticado na sessao';
        END IF;
        SELECT perfil, id_restaurante, ativo
          INTO v_perfil, v_id_restaurante_usuario, v_usuario_ativo
        FROM usuario WHERE id_usuario = @app_id_usuario;
        IF v_usuario_ativo <> 1 OR v_perfil NOT IN ('RESTAURANTE','GERENTE','ADMINISTRADOR') THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Perfil sem permissao para alterar preco';
        END IF;
        IF v_perfil = 'RESTAURANTE' AND v_id_restaurante_usuario <> OLD.id_restaurante THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Usuario Restaurante so pode alterar produtos do proprio estabelecimento';
        END IF;
    END IF;
END$$

CREATE TRIGGER trg_produto_au
AFTER UPDATE ON produto
FOR EACH ROW
BEGIN
    IF NEW.preco_tabela <> OLD.preco_tabela THEN
        SET @permitir_historico_preco = 1;
        INSERT INTO historico_preco (
            id_produto, id_usuario, preco_anterior, preco_novo, data_alteracao
        ) VALUES (
            NEW.id_produto, @app_id_usuario, OLD.preco_tabela, NEW.preco_tabela, CURRENT_TIMESTAMP
        );
        SET @permitir_historico_preco = NULL;
    END IF;
END$$

CREATE TRIGGER trg_entrega_bi
BEFORE INSERT ON entrega
FOR EACH ROW
BEGIN
    DECLARE v_ativo TINYINT;
    DECLARE v_situacao_entregador VARCHAR(20);
    DECLARE v_abertas INT DEFAULT 0;
    DECLARE v_situacao_pedido VARCHAR(20);

    SELECT ativo, situacao INTO v_ativo, v_situacao_entregador
    FROM entregador WHERE id_entregador = NEW.id_entregador FOR UPDATE;
    IF v_ativo <> 1 OR v_situacao_entregador NOT IN ('DISPONIVEL','EM_ENTREGA') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Entregador indisponivel para nova entrega';
    END IF;

    SELECT COUNT(*) INTO v_abertas
    FROM entrega
    WHERE id_entregador = NEW.id_entregador AND situacao IN ('ATRIBUIDA','COLETADA');
    IF v_abertas >= 2 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Entregador ja possui duas entregas em aberto';
    END IF;

    SELECT situacao INTO v_situacao_pedido FROM pedido WHERE id_pedido = NEW.id_pedido;
    IF v_situacao_pedido <> 'PRONTO' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Entrega so pode ser atribuida a pedido PRONTO';
    END IF;
    SET NEW.data_atribuicao = CURRENT_TIMESTAMP;
    SET NEW.data_coleta = NULL;
    SET NEW.data_entrega = NULL;
    SET NEW.situacao = 'ATRIBUIDA';
END$$

CREATE TRIGGER trg_entrega_bu
BEFORE UPDATE ON entrega
FOR EACH ROW
BEGIN
    DECLARE v_tem_alcool TINYINT DEFAULT 0;
    DECLARE v_data_nascimento DATE;
    DECLARE v_data_pedido DATETIME;

    IF OLD.situacao IN ('CONCLUIDA','CANCELADA') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Entrega encerrada e imutavel';
    END IF;
    IF NEW.data_atribuicao <> OLD.data_atribuicao THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'data_atribuicao e gerada pelo servidor';
    END IF;
    IF NOT (NEW.data_coleta <=> OLD.data_coleta) AND NOT (NEW.situacao = 'COLETADA' AND OLD.situacao = 'ATRIBUIDA') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'data_coleta e gerada pelo servidor';
    END IF;
    IF NOT (NEW.data_entrega <=> OLD.data_entrega) AND NOT (NEW.situacao = 'CONCLUIDA' AND OLD.situacao = 'COLETADA') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'data_entrega e gerada pelo servidor';
    END IF;

    IF NEW.situacao <> OLD.situacao THEN
        IF COALESCE(@permitir_atualizacao_entrega, 0) <> 1 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Use sp_atualizar_entrega para alterar a situacao da entrega';
        END IF;
        IF NOT (
            (OLD.situacao = 'ATRIBUIDA' AND NEW.situacao IN ('COLETADA','CANCELADA')) OR
            (OLD.situacao = 'COLETADA' AND NEW.situacao IN ('CONCLUIDA','CANCELADA'))
        ) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Transicao de situacao da entrega nao permitida';
        END IF;
    END IF;

    IF NEW.situacao = 'COLETADA' AND OLD.situacao = 'ATRIBUIDA' THEN
        SET NEW.data_coleta = CURRENT_TIMESTAMP;
    END IF;

    IF NEW.situacao = 'CONCLUIDA' AND OLD.situacao <> 'CONCLUIDA' THEN
        SELECT p.data_pedido, c.data_nascimento
          INTO v_data_pedido, v_data_nascimento
        FROM pedido p JOIN cliente c ON c.id_cliente = p.id_cliente
        WHERE p.id_pedido = NEW.id_pedido;

        SELECT EXISTS(
            SELECT 1 FROM item_pedido ip JOIN produto pr ON pr.id_produto = ip.id_produto
            WHERE ip.id_pedido = NEW.id_pedido AND pr.alcoolico = 1
        ) INTO v_tem_alcool;

        IF v_tem_alcool = 1 THEN
            IF NEW.maioridade_conferida <> 1 THEN
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Entrega com bebida alcoolica exige conferencia de maioridade';
            END IF;
            IF v_data_nascimento IS NULL OR TIMESTAMPDIFF(YEAR, v_data_nascimento, DATE(v_data_pedido)) < 18 THEN
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cliente menor de 18 anos nao pode receber bebida alcoolica';
            END IF;
        END IF;
        SET NEW.data_entrega = CURRENT_TIMESTAMP;
    END IF;
END$$

CREATE TRIGGER trg_entrega_ai
AFTER INSERT ON entrega
FOR EACH ROW
BEGIN
    UPDATE entregador SET situacao = 'EM_ENTREGA' WHERE id_entregador = NEW.id_entregador AND ativo = 1;
    SET @permitir_inicio_entrega = 1;
    UPDATE pedido SET situacao = 'EM_ROTA' WHERE id_pedido = NEW.id_pedido AND situacao = 'PRONTO';
    SET @permitir_inicio_entrega = NULL;
END$$

CREATE TRIGGER trg_entrega_au
AFTER UPDATE ON entrega
FOR EACH ROW
BEGIN
    IF NEW.situacao = 'CONCLUIDA' AND OLD.situacao <> 'CONCLUIDA' THEN
        SET @permitir_entrega = 1;
        UPDATE pedido SET situacao = 'ENTREGUE'
        WHERE id_pedido = NEW.id_pedido AND situacao = 'EM_ROTA';
        SET @permitir_entrega = NULL;
    END IF;
END$$

CREATE TRIGGER trg_estorno_bi
BEFORE INSERT ON estorno
FOR EACH ROW
BEGIN
    DECLARE v_valor_pagamento DECIMAL(10,2);
    DECLARE v_ja_estornado DECIMAL(10,2) DEFAULT 0.00;
    DECLARE v_perfil VARCHAR(20);

    IF COALESCE(@permitir_estorno, 0) <> 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Use sp_solicitar_estorno ou a rotina automatica de cancelamento';
    END IF;

    SELECT valor INTO v_valor_pagamento
    FROM pagamento WHERE id_pagamento = NEW.id_pagamento FOR UPDATE;

    SELECT COALESCE(SUM(valor), 0.00) INTO v_ja_estornado
    FROM estorno
    WHERE id_pagamento = NEW.id_pagamento AND situacao <> 'NEGADO';

    IF v_ja_estornado + NEW.valor > v_valor_pagamento THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Soma dos estornos excede o valor do pagamento';
    END IF;

    IF NEW.situacao IN ('APROVADO','NEGADO') THEN
        IF NEW.id_usuario IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Decisao de estorno exige usuario do suporte';
        END IF;
        SELECT perfil INTO v_perfil FROM usuario WHERE id_usuario = NEW.id_usuario;
        IF v_perfil <> 'SUPORTE' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Somente usuario SUPORTE pode decidir estorno';
        END IF;
    END IF;

    SET NEW.data_solicitacao = CURRENT_TIMESTAMP;
    IF NEW.situacao = 'CONCLUIDO' AND NEW.data_conclusao IS NULL THEN
        SET NEW.data_conclusao = CURRENT_TIMESTAMP;
    END IF;
END$$

CREATE TRIGGER trg_estorno_bu
BEFORE UPDATE ON estorno
FOR EACH ROW
BEGIN
    DECLARE v_valor_pagamento DECIMAL(10,2);
    DECLARE v_ja_estornado DECIMAL(10,2) DEFAULT 0.00;
    DECLARE v_perfil VARCHAR(20);

    IF NEW.data_solicitacao <> OLD.data_solicitacao THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'data_solicitacao e gerada pelo servidor';
    END IF;
    IF NOT (NEW.data_conclusao <=> OLD.data_conclusao) AND NOT (NEW.situacao = 'CONCLUIDO' AND OLD.situacao = 'APROVADO') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'data_conclusao e gerada pelo servidor';
    END IF;
    IF NEW.id_pagamento <> OLD.id_pagamento OR NEW.valor <> OLD.valor THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Pagamento e valor do estorno sao imutaveis';
    END IF;

    SELECT valor INTO v_valor_pagamento
    FROM pagamento WHERE id_pagamento = NEW.id_pagamento FOR UPDATE;
    SELECT COALESCE(SUM(valor), 0.00) INTO v_ja_estornado
    FROM estorno
    WHERE id_pagamento = NEW.id_pagamento
      AND id_estorno <> OLD.id_estorno
      AND situacao <> 'NEGADO';
    IF NEW.situacao <> 'NEGADO' AND v_ja_estornado + NEW.valor > v_valor_pagamento THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Soma dos estornos excede o valor do pagamento';
    END IF;

    IF NEW.situacao <> OLD.situacao AND NOT (
        (OLD.situacao = 'SOLICITADO' AND NEW.situacao IN ('EM_ANALISE','APROVADO','NEGADO')) OR
        (OLD.situacao = 'EM_ANALISE' AND NEW.situacao IN ('APROVADO','NEGADO')) OR
        (OLD.situacao = 'APROVADO' AND NEW.situacao = 'CONCLUIDO')
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Transicao de situacao do estorno nao permitida';
    END IF;

    IF NEW.situacao IN ('APROVADO','NEGADO') AND OLD.situacao NOT IN ('APROVADO','NEGADO') THEN
        IF NEW.id_usuario IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Decisao de estorno exige usuario do suporte';
        END IF;
        SELECT perfil INTO v_perfil FROM usuario WHERE id_usuario = NEW.id_usuario;
        IF v_perfil <> 'SUPORTE' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Somente usuario SUPORTE pode decidir estorno';
        END IF;
    END IF;
    IF NEW.situacao = 'CONCLUIDO' AND OLD.situacao <> 'CONCLUIDO' THEN
        SET NEW.data_conclusao = CURRENT_TIMESTAMP;
    END IF;
END$$

CREATE TRIGGER trg_estorno_au
AFTER UPDATE ON estorno
FOR EACH ROW
BEGIN
    DECLARE v_total_concluido DECIMAL(10,2) DEFAULT 0.00;
    DECLARE v_valor_pagamento DECIMAL(10,2) DEFAULT 0.00;
    IF NEW.situacao = 'CONCLUIDO' AND OLD.situacao <> 'CONCLUIDO' THEN
        SELECT COALESCE(SUM(valor),0.00) INTO v_total_concluido
        FROM estorno WHERE id_pagamento = NEW.id_pagamento AND situacao = 'CONCLUIDO';
        SELECT valor INTO v_valor_pagamento FROM pagamento WHERE id_pagamento = NEW.id_pagamento;
        IF v_total_concluido >= v_valor_pagamento THEN
            UPDATE pagamento SET situacao = 'ESTORNADO' WHERE id_pagamento = NEW.id_pagamento;
        END IF;
    END IF;
END$$

CREATE TRIGGER trg_avaliacao_bi
BEFORE INSERT ON avaliacao
FOR EACH ROW
BEGIN
    DECLARE v_situacao VARCHAR(20);
    DECLARE v_data_entrega DATETIME;
    SELECT p.situacao, e.data_entrega
      INTO v_situacao, v_data_entrega
    FROM pedido p JOIN entrega e ON e.id_pedido = p.id_pedido
    WHERE p.id_pedido = NEW.id_pedido;

    IF v_situacao <> 'ENTREGUE' OR v_data_entrega IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Somente pedidos ENTREGUE podem ser avaliados';
    END IF;
    IF CURRENT_TIMESTAMP > v_data_entrega + INTERVAL 7 DAY THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Prazo de avaliacao de 7 dias expirado';
    END IF;
    SET NEW.data_avaliacao = CURRENT_TIMESTAMP;
END$$

-- ============================================================================
-- 12. TRIGGERS DE TIMESTAMP CONTROLADO PELO SERVIDOR
-- ============================================================================


CREATE TRIGGER trg_avaliacao_bu
BEFORE UPDATE ON avaliacao
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Avaliacao registrada e imutavel';
END$$

CREATE TRIGGER trg_pagamento_bi
BEFORE INSERT ON pagamento
FOR EACH ROW
BEGIN
    DECLARE v_situacao_pedido VARCHAR(20);
    DECLARE v_forma_ativa TINYINT;
    SELECT situacao INTO v_situacao_pedido FROM pedido WHERE id_pedido = NEW.id_pedido;
    SELECT ativo INTO v_forma_ativa FROM forma_pagamento WHERE id_forma_pagamento = NEW.id_forma_pagamento;
    IF v_situacao_pedido <> 'CRIADO' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Pagamento deve ser registrado antes da confirmacao do pedido';
    END IF;
    IF v_forma_ativa <> 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Forma de pagamento inativa';
    END IF;
    SET NEW.data_pagamento = CURRENT_TIMESTAMP;
END$$

CREATE TRIGGER trg_pagamento_bu
BEFORE UPDATE ON pagamento
FOR EACH ROW
BEGIN
    IF NEW.data_pagamento <> OLD.data_pagamento THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'data_pagamento e gerada pelo servidor';
    END IF;
    IF NEW.id_pedido <> OLD.id_pedido OR NEW.id_forma_pagamento <> OLD.id_forma_pagamento OR NEW.valor <> OLD.valor THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Pedido, forma e valor do pagamento sao imutaveis apos o registro';
    END IF;
    IF NEW.situacao <> OLD.situacao AND NOT (
        (OLD.situacao = 'PENDENTE' AND NEW.situacao IN ('APROVADO','RECUSADO','ESTORNADO')) OR
        (OLD.situacao = 'APROVADO' AND NEW.situacao = 'ESTORNADO')
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Transicao de situacao do pagamento nao permitida';
    END IF;
END$$

CREATE TRIGGER trg_historico_status_bu
BEFORE UPDATE ON historico_status_pedido
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Historico de status e append-only';
END$$

CREATE TRIGGER trg_historico_status_bd
BEFORE DELETE ON historico_status_pedido
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Historico de status nao pode ser excluido';
END$$

CREATE TRIGGER trg_log_auditoria_bu
BEFORE UPDATE ON log_auditoria
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Log de auditoria e append-only';
END$$

CREATE TRIGGER trg_log_auditoria_bd
BEFORE DELETE ON log_auditoria
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Log de auditoria nao pode ser excluido';
END$$

-- ============================================================================
-- 13. TRIGGERS DE AUDITORIA (RNF01 / RNF12 / PR05)
-- As capturas evitam gravar CPF, telefone cifrado, senha ou token em claro.
-- ============================================================================

CREATE TRIGGER trg_aud_cliente_ai
AFTER INSERT ON cliente
FOR EACH ROW
BEGIN
    CALL sp_registrar_auditoria('INSERT','cliente',NEW.id_cliente,NULL,
      JSON_OBJECT('nome',NEW.nome,'cpf_hash',NEW.cpf_hash,
                  'email_mascarado',IF(NEW.email IS NULL,NULL,CONCAT(LEFT(NEW.email,1),'***@',SUBSTRING_INDEX(NEW.email,'@',-1))),
                  'ativo',NEW.ativo,'data_anonimizacao',NEW.data_anonimizacao));
END$$

CREATE TRIGGER trg_aud_cliente_au
AFTER UPDATE ON cliente
FOR EACH ROW
BEGIN
    CALL sp_registrar_auditoria(
      IF(OLD.ativo=1 AND NEW.ativo=0,'DELETE_LOGICO','UPDATE'), 'cliente', NEW.id_cliente,
      JSON_OBJECT('nome',OLD.nome,'cpf_hash',OLD.cpf_hash,'ativo',OLD.ativo),
      JSON_OBJECT('nome',NEW.nome,'cpf_hash',NEW.cpf_hash,
                  'email_mascarado',IF(NEW.email IS NULL,NULL,CONCAT(LEFT(NEW.email,1),'***@',SUBSTRING_INDEX(NEW.email,'@',-1))),
                  'ativo',NEW.ativo,'data_anonimizacao',NEW.data_anonimizacao));
END$$

CREATE TRIGGER trg_aud_entregador_ai
AFTER INSERT ON entregador
FOR EACH ROW
BEGIN
    CALL sp_registrar_auditoria('INSERT','entregador',NEW.id_entregador,NULL,
      JSON_OBJECT('nome',NEW.nome,'cpf_hash',NEW.cpf_hash,'tipo_veiculo',NEW.tipo_veiculo,'situacao',NEW.situacao,'ativo',NEW.ativo));
END$$

CREATE TRIGGER trg_aud_entregador_au
AFTER UPDATE ON entregador
FOR EACH ROW
BEGIN
    CALL sp_registrar_auditoria(IF(OLD.ativo=1 AND NEW.ativo=0,'DELETE_LOGICO','UPDATE'), 'entregador', NEW.id_entregador,
      JSON_OBJECT('nome',OLD.nome,'situacao',OLD.situacao,'ativo',OLD.ativo),
      JSON_OBJECT('nome',NEW.nome,'cpf_hash',NEW.cpf_hash,'situacao',NEW.situacao,'ativo',NEW.ativo,'data_anonimizacao',NEW.data_anonimizacao));
END$$

CREATE TRIGGER trg_aud_restaurante_ai
AFTER INSERT ON restaurante
FOR EACH ROW
BEGIN
    CALL sp_registrar_auditoria('INSERT','restaurante',NEW.id_restaurante,NULL,
      JSON_OBJECT('nome_fantasia',NEW.nome_fantasia,'cnpj',NEW.cnpj,'situacao',NEW.situacao,'ativo',NEW.ativo));
END$$

CREATE TRIGGER trg_aud_restaurante_au
AFTER UPDATE ON restaurante
FOR EACH ROW
BEGIN
    CALL sp_registrar_auditoria(IF(OLD.ativo=1 AND NEW.ativo=0,'DELETE_LOGICO','UPDATE'), 'restaurante', NEW.id_restaurante,
      JSON_OBJECT('nome_fantasia',OLD.nome_fantasia,'situacao',OLD.situacao,'ativo',OLD.ativo),
      JSON_OBJECT('nome_fantasia',NEW.nome_fantasia,'cnpj',NEW.cnpj,'situacao',NEW.situacao,'ativo',NEW.ativo));
END$$

CREATE TRIGGER trg_aud_produto_ai
AFTER INSERT ON produto
FOR EACH ROW
BEGIN
    CALL sp_registrar_auditoria('INSERT','produto',NEW.id_produto,NULL,
      JSON_OBJECT('id_restaurante',NEW.id_restaurante,'nome',NEW.nome,'preco_tabela',NEW.preco_tabela,'ativo',NEW.ativo,'disponivel',NEW.disponivel));
END$$

CREATE TRIGGER trg_aud_produto_au
AFTER UPDATE ON produto
FOR EACH ROW
BEGIN
    CALL sp_registrar_auditoria(IF(OLD.ativo=1 AND NEW.ativo=0,'DELETE_LOGICO','UPDATE'), 'produto', NEW.id_produto,
      JSON_OBJECT('nome',OLD.nome,'preco_tabela',OLD.preco_tabela,'ativo',OLD.ativo,'disponivel',OLD.disponivel),
      JSON_OBJECT('nome',NEW.nome,'preco_tabela',NEW.preco_tabela,'ativo',NEW.ativo,'disponivel',NEW.disponivel));
END$$

CREATE TRIGGER trg_aud_pedido_ai
AFTER INSERT ON pedido
FOR EACH ROW
BEGIN
    CALL sp_registrar_auditoria('INSERT','pedido',NEW.id_pedido,NULL,
      JSON_OBJECT('id_cliente',NEW.id_cliente,'id_restaurante',NEW.id_restaurante,'situacao',NEW.situacao,'data_pedido',NEW.data_pedido));
END$$

CREATE TRIGGER trg_aud_pedido_au
AFTER UPDATE ON pedido
FOR EACH ROW
BEGIN
    CALL sp_registrar_auditoria('UPDATE','pedido',NEW.id_pedido,
      JSON_OBJECT('situacao',OLD.situacao,'taxa_entrega',OLD.taxa_entrega,'valor_desconto',OLD.valor_desconto),
      JSON_OBJECT('situacao',NEW.situacao,'taxa_entrega',NEW.taxa_entrega,'valor_desconto',NEW.valor_desconto,'origem_cancelamento',NEW.origem_cancelamento));
END$$

CREATE TRIGGER trg_aud_pagamento_ai
AFTER INSERT ON pagamento
FOR EACH ROW
BEGIN
    CALL sp_registrar_auditoria('INSERT','pagamento',NEW.id_pagamento,NULL,
      JSON_OBJECT('id_pedido',NEW.id_pedido,'valor',NEW.valor,'situacao',NEW.situacao,'ultimos_digitos',NEW.ultimos_digitos,'codigo_transacao_gateway',NEW.codigo_transacao_gateway));
END$$

CREATE TRIGGER trg_aud_pagamento_au
AFTER UPDATE ON pagamento
FOR EACH ROW
BEGIN
    CALL sp_registrar_auditoria('UPDATE','pagamento',NEW.id_pagamento,
      JSON_OBJECT('valor',OLD.valor,'situacao',OLD.situacao),
      JSON_OBJECT('valor',NEW.valor,'situacao',NEW.situacao,'ultimos_digitos',NEW.ultimos_digitos,'codigo_transacao_gateway',NEW.codigo_transacao_gateway));
END$$

CREATE TRIGGER trg_aud_estorno_ai
AFTER INSERT ON estorno
FOR EACH ROW
BEGIN
    CALL sp_registrar_auditoria('INSERT','estorno',NEW.id_estorno,NULL,
      JSON_OBJECT('id_pagamento',NEW.id_pagamento,'valor',NEW.valor,'situacao',NEW.situacao,'motivo',NEW.motivo));
END$$

CREATE TRIGGER trg_aud_estorno_au
AFTER UPDATE ON estorno
FOR EACH ROW
BEGIN
    CALL sp_registrar_auditoria('UPDATE','estorno',NEW.id_estorno,
      JSON_OBJECT('valor',OLD.valor,'situacao',OLD.situacao),
      JSON_OBJECT('valor',NEW.valor,'situacao',NEW.situacao,'motivo',NEW.motivo));
END$$

CREATE TRIGGER trg_aud_usuario_ai
AFTER INSERT ON usuario
FOR EACH ROW
BEGIN
    CALL sp_registrar_auditoria('INSERT','usuario',NEW.id_usuario,NULL,
      JSON_OBJECT('nome',NEW.nome,'login',NEW.login,'perfil',NEW.perfil,'ativo',NEW.ativo));
END$$

CREATE TRIGGER trg_aud_usuario_au
AFTER UPDATE ON usuario
FOR EACH ROW
BEGIN
    CALL sp_registrar_auditoria(IF(OLD.ativo=1 AND NEW.ativo=0,'DELETE_LOGICO','UPDATE'), 'usuario', NEW.id_usuario,
      JSON_OBJECT('nome',OLD.nome,'login',OLD.login,'perfil',OLD.perfil,'ativo',OLD.ativo),
      JSON_OBJECT('nome',NEW.nome,'login',NEW.login,'perfil',NEW.perfil,'ativo',NEW.ativo));
END$$

CREATE TRIGGER trg_aud_cupom_ai
AFTER INSERT ON cupom
FOR EACH ROW
BEGIN
    CALL sp_registrar_auditoria('INSERT','cupom',NEW.id_cupom,NULL,
      JSON_OBJECT('codigo',NEW.codigo,'tipo_desconto',NEW.tipo_desconto,'valor_beneficio',NEW.valor_beneficio,'ativo',NEW.ativo));
END$$

CREATE TRIGGER trg_aud_cupom_au
AFTER UPDATE ON cupom
FOR EACH ROW
BEGIN
    CALL sp_registrar_auditoria(IF(OLD.ativo=1 AND NEW.ativo=0,'DELETE_LOGICO','UPDATE'), 'cupom', NEW.id_cupom,
      JSON_OBJECT('codigo',OLD.codigo,'valor_beneficio',OLD.valor_beneficio,'ativo',OLD.ativo),
      JSON_OBJECT('codigo',NEW.codigo,'valor_beneficio',NEW.valor_beneficio,'ativo',NEW.ativo));
END$$


-- Timestamps adicionais controlados pelo servidor e historicos append-only.
CREATE TRIGGER trg_historico_preco_bi
BEFORE INSERT ON historico_preco
FOR EACH ROW
BEGIN
    IF COALESCE(@permitir_historico_preco, 0) <> 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Historico de preco e gerado pelo sistema';
    END IF;
    SET NEW.data_alteracao = CURRENT_TIMESTAMP;
END$$

CREATE TRIGGER trg_historico_preco_bu
BEFORE UPDATE ON historico_preco
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Historico de preco e imutavel';
END$$

CREATE TRIGGER trg_historico_preco_bd
BEFORE DELETE ON historico_preco
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Historico de preco nao pode ser excluido';
END$$

CREATE TRIGGER trg_historico_status_bi
BEFORE INSERT ON historico_status_pedido
FOR EACH ROW
BEGIN
    IF COALESCE(@permitir_historico_status, 0) <> 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Historico de status e gerado pelo sistema';
    END IF;
    SET NEW.data_mudanca = CURRENT_TIMESTAMP;
END$$

CREATE TRIGGER trg_log_auditoria_bi
BEFORE INSERT ON log_auditoria
FOR EACH ROW
BEGIN
    IF COALESCE(@permitir_log_auditoria, 0) <> 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Log de auditoria e gerado por rotinas internas';
    END IF;
    SET NEW.data_evento = CURRENT_TIMESTAMP;
    SET NEW.ip_origem = COALESCE(@app_ip_origem, NEW.ip_origem, 'NAO_INFORMADO');
END$$

CREATE TRIGGER trg_solicitacao_titular_bi
BEFORE INSERT ON solicitacao_titular
FOR EACH ROW
BEGIN
    SET NEW.data_solicitacao = CURRENT_TIMESTAMP;
END$$

CREATE TRIGGER trg_solicitacao_titular_bu
BEFORE UPDATE ON solicitacao_titular
FOR EACH ROW
BEGIN
    DECLARE v_perfil VARCHAR(20);
    IF NEW.data_solicitacao <> OLD.data_solicitacao THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'data_solicitacao e gerada pelo servidor';
    END IF;
    IF NEW.situacao <> OLD.situacao AND NOT (
        (OLD.situacao = 'ABERTA' AND NEW.situacao IN ('EM_ATENDIMENTO','CONCLUIDA','NEGADA')) OR
        (OLD.situacao = 'EM_ATENDIMENTO' AND NEW.situacao IN ('CONCLUIDA','NEGADA'))
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Transicao de solicitacao do titular invalida';
    END IF;
    IF NEW.situacao IN ('EM_ATENDIMENTO','CONCLUIDA','NEGADA') AND NEW.situacao <> OLD.situacao THEN
        IF @app_id_usuario IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Atendimento da solicitacao exige usuario interno';
        END IF;
        SELECT perfil INTO v_perfil FROM usuario WHERE id_usuario = @app_id_usuario AND ativo = 1;
        IF v_perfil NOT IN ('SUPORTE','ADMINISTRADOR') THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Perfil sem permissao para atender solicitacao LGPD';
        END IF;
    END IF;
    IF NEW.situacao = 'CONCLUIDA' AND OLD.situacao <> 'CONCLUIDA' THEN
        SET NEW.data_conclusao = CURRENT_TIMESTAMP;
    ELSEIF NOT (NEW.data_conclusao <=> OLD.data_conclusao) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'data_conclusao e controlada pelo servidor';
    END IF;
END$$

CREATE TRIGGER trg_pedido_bd
BEFORE DELETE ON pedido
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Pedido nao pode ser excluido fisicamente';
END$$

CREATE TRIGGER trg_pagamento_bd
BEFORE DELETE ON pagamento
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Pagamento deve ser preservado para auditoria';
END$$

CREATE TRIGGER trg_estorno_bd
BEFORE DELETE ON estorno
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Estorno deve ser preservado para auditoria';
END$$

CREATE TRIGGER trg_entrega_bd
BEFORE DELETE ON entrega
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Historico de entrega nao pode ser excluido';
END$$

CREATE TRIGGER trg_avaliacao_bd
BEFORE DELETE ON avaliacao
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Avaliacao nao pode ser excluida fisicamente';
END$$

CREATE TRIGGER trg_cliente_bd
BEFORE DELETE ON cliente
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Use inativacao ou sp_anonimizar_titular; DELETE fisico proibido';
END$$

CREATE TRIGGER trg_entregador_bd
BEFORE DELETE ON entregador
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Use inativacao ou sp_anonimizar_titular; DELETE fisico proibido';
END$$

CREATE TRIGGER trg_restaurante_bd
BEFORE DELETE ON restaurante
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Restaurante deve ser inativado, nao excluido';
END$$

CREATE TRIGGER trg_produto_bd
BEFORE DELETE ON produto
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Produto deve ser inativado, nao excluido';
END$$

CREATE TRIGGER trg_usuario_bd
BEFORE DELETE ON usuario
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Usuario deve ser inativado, nao excluido';
END$$

CREATE TRIGGER trg_cupom_bd
BEFORE DELETE ON cupom
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cupom deve ser inativado, nao excluido';
END$$

CREATE TRIGGER trg_endereco_cliente_bd
BEFORE DELETE ON endereco_cliente
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Endereco deve ser inativado, nao excluido';
END$$


DELIMITER ;

-- ============================================================================
-- 14. OBSERVACOES OPERACIONAIS E PONTOS DE CONTROLE
-- ============================================================================
-- A. Antes de alterar preco_tabela, a aplicacao deve definir @app_id_usuario.
--    O trigger trg_produto_au grava o historico_preco automaticamente.
-- B. Para finalizar pedido, a aplicacao deve abrir START TRANSACTION, inserir
--    pedido, itens e pagamentos, chamar sp_confirmar_pedido(id) e entao COMMIT.
--    A procedure exige transacao ativa; em falha faz ROLLBACK integral. Ela
--    bloqueia pedido, cliente, cupom e pagamentos e valida os requisitos.
-- C. A atribuicao de entrega deve ser feita com INSERT em entrega para pedido
--    PRONTO. O trigger atualiza pedido para EM_ROTA e entregador para EM_ENTREGA.
-- D. Alteracoes de estado da entrega devem usar CALL sp_atualizar_entrega(id,
--    'COLETADA'|'CONCLUIDA'|'CANCELADA', distancia_km, maioridade_conferida).
--    A rotina recalcula a disponibilidade do entregador ao final da transacao.
-- E. A avaliacao deve ser inserida na tabela avaliacao; o trigger limita a
--    inclusao a pedidos entregues ha no maximo 7 dias.
-- F. Estorno por arrependimento apos entrega deve usar CALL sp_solicitar_estorno.
--    Cancelamentos geram os estornos automaticamente conforme RN14.
-- G. CPF: a aplicacao deve chamar fn_valida_cpf(cpf_em_texto) antes de cifrar;
--    armazenar cpf_cifrado e cpf_hash HMAC-SHA-256, nunca o CPF puro.
-- H. CNPJ: restaurante.cnpj e validado pelas triggers usando fn_valida_cnpj().
-- I. Nao conceder DELETE/UPDATE em log_auditoria a usuarios da aplicacao.
--    As triggers bloqueiam UPDATE e DELETE; o controle de acesso deve reforcar.
-- J. A restricao UNIQUE funcional de endereco_cliente garante no maximo um
--    endereco principal ativo por cliente. A garantia de pelo menos um endereco
--    principal ativo deve ser concluida pela transacao/procedure de cadastro.
-- K. O evento ev_anonimizacao_diaria depende de event_scheduler=ON no servidor.
-- L. A carga inicial contem exatamente cinco formas de pagamento, conforme RF15.
-- M. CPF e validado em texto puro antes da cifragem pela aplicacao; o banco
--    recebe apenas cpf_cifrado e cpf_hash HMAC-SHA-256. Nao grave CPF em claro.
-- N. A aplicacao deve implementar integralmente a matriz RBAC da secao 3.1,
--    inclusive filtros de leitura por titular/restaurante e eventos de acesso.
-- O. Conceda a contas da aplicacao somente privilegios minimos. A tabela
--    log_auditoria deve ter SELECT para perfis autorizados; INSERT ocorre por
--    rotinas internas/DEFINER; UPDATE e DELETE devem ser negados.
-- P. O script usa valores mestre para forma_pagamento; demais cadastros sao
--    inseridos pela aplicacao, respeitando as procedures e as permissoes.
-- Q. O timezone America/Sao_Paulo deve estar carregado nas tabelas de fuso do MySQL.
-- R. Algumas garantias de concorrencia/seguranca tambem dependem dos privilegios
--    SQL, do nivel REPEATABLE READ e da configuracao da aplicacao.
-- ============================================================================
