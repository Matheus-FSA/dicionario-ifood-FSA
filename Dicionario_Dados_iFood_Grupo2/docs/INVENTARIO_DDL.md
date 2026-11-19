# Inventário extraído do DDL

### cidade — 3 colunas

id_cidade, nome, uf

### categoria_restaurante — 3 colunas

id_categoria_restaurante, nome, ativo

### forma_pagamento — 4 colunas

id_forma_pagamento, nome, exige_pagamento_online, ativo

### cupom — 9 colunas

id_cupom, codigo, tipo_desconto, valor_beneficio, valor_pedido_minimo, data_inicio, data_fim, limite_uso_por_cliente, ativo

### cliente — 13 colunas

id_cliente, nome, cpf_hash, cpf_cifrado, email, telefone_cifrado, data_nascimento, senha_hash, data_consentimento, versao_termo_consentimento, data_revogacao_consentimento, data_anonimizacao, ativo

### entregador — 10 colunas

id_entregador, nome, cpf_hash, cpf_cifrado, telefone_cifrado, tipo_veiculo, senha_hash, situacao, data_anonimizacao, ativo

### restaurante — 21 colunas

id_restaurante, id_categoria_restaurante, id_cidade, razao_social, nome_fantasia, cnpj, telefone, cep, logradouro, numero, complemento, bairro, latitude, longitude, valor_pedido_minimo, raio_entrega_km, taxa_entrega_base, taxa_entrega_por_km, percentual_comissao, situacao, ativo

### usuario — 7 colunas

id_usuario, id_restaurante, nome, login, senha_hash, perfil, ativo

### endereco_cliente — 14 colunas

id_endereco_cliente, id_cliente, id_cidade, apelido, logradouro, numero, complemento, bairro, cep, latitude, longitude, principal, ativo, id_cliente_principal_ativo

### horario_funcionamento — 5 colunas

id_horario_funcionamento, id_restaurante, dia_semana, hora_abertura, hora_fechamento

### categoria_produto — 4 colunas

id_categoria_produto, id_restaurante, nome, ativo

### produto — 9 colunas

id_produto, id_restaurante, id_categoria_produto, nome, descricao, preco_tabela, alcoolico, disponivel, ativo

### historico_preco — 6 colunas

id_historico_preco, id_produto, id_usuario, preco_anterior, preco_novo, data_alteracao

### pedido — 14 colunas

id_pedido, id_cliente, id_restaurante, id_endereco_cliente, id_cupom, data_pedido, situacao, taxa_entrega, valor_desconto, percentual_comissao_aplicado, motivo_cancelamento, origem_cancelamento, id_usuario_cancelamento, data_cancelamento

### item_pedido — 6 colunas

id_item_pedido, id_pedido, id_produto, quantidade, preco_unitario_venda, observacao

### pagamento — 9 colunas

id_pagamento, id_pedido, id_forma_pagamento, valor, situacao, token_cartao, ultimos_digitos, codigo_transacao_gateway, data_pagamento

### historico_status_pedido — 6 colunas

id_historico_status_pedido, id_pedido, id_usuario, situacao_anterior, situacao_nova, data_mudanca

### estorno — 8 colunas

id_estorno, id_pagamento, id_usuario, valor, motivo, situacao, data_solicitacao, data_conclusao

### entrega — 9 colunas

id_entrega, id_pedido, id_entregador, data_atribuicao, data_coleta, data_entrega, distancia_km, maioridade_conferida, situacao

### avaliacao — 6 colunas

id_avaliacao, id_pedido, nota_restaurante, nota_entrega, comentario, data_avaliacao

### log_auditoria — 11 colunas

id_log_auditoria, id_usuario, id_cliente, id_entregador, operacao, tabela_afetada, id_registro_afetado, valor_anterior, valor_novo, data_evento, ip_origem

### solicitacao_titular — 8 colunas

id_solicitacao_titular, id_cliente, id_entregador, id_usuario, tipo, situacao, data_solicitacao, data_conclusao
