require 'rails_helper'

RSpec.describe Clientes::SalvarService, type: :service do
  let(:empresa) { create(:empresa) }
  let(:outra_empresa) { create(:empresa) }

  describe 'alias de serviço' do
    it 'permite chamar através de Clientes::CadastrarService' do
      expect(Clientes::CadastrarService).to eq(Clientes::SalvarService)
      result = Clientes::CadastrarService.call(
        empresa: empresa,
        nome: 'Maria da Silva'
      )
      expect(result).to be_success
      expect(result.data[:cliente].nome).to eq('Maria da Silva')
    end
  end

  describe 'criação de cliente (cadastro simples)' do
    it 'cria cliente com sucesso utilizando atributos em hash' do
      result = described_class.call(
        empresa: empresa,
        atributos: {
          nome: 'Carlos Drummond',
          email: 'carlos@poesia.com.br',
          telefone: '85988887777',
          documento: '123.456.789-00'
        }
      )

      expect(result).to be_success
      cliente = result.data[:cliente]
      expect(cliente).to be_persisted
      expect(cliente.nome).to eq('Carlos Drummond')
      expect(cliente.email).to eq('carlos@poesia.com.br')
      expect(cliente.telefone).to eq('85988887777')
      expect(cliente.documento).to eq('12345678900') # sanitizado
      expect(cliente.empresa).to eq(empresa)
      expect(cliente.ativo).to be true
      expect(cliente.aceita_marketing).to be true
      expect(result.data[:endereco]).to be_nil
      expect(result.data[:endereco_padrao]).to be_nil
    end

    it 'cria cliente com sucesso utilizando argumentos nomeados diretos (kwargs)' do
      result = described_class.call(
        empresa: empresa,
        nome: 'Clarice Lispector',
        email: 'clarice@literatura.com',
        telefone: '11977776666',
        documento: '98765432100',
        aceita_marketing: false
      )

      expect(result).to be_success
      cliente = result.data[:cliente]
      expect(cliente.nome).to eq('Clarice Lispector')
      expect(cliente.aceita_marketing).to be false
    end

    it 'aceita empresa informada por ID numérico' do
      result = described_class.call(
        empresa: empresa.id,
        nome: 'Machado de Assis'
      )

      expect(result).to be_success
      expect(result.data[:cliente].empresa_id).to eq(empresa.id)
    end
  end

  describe 'criação de cliente com endereço aninhado' do
    let(:endereco_params) do
      {
        titulo: 'Residencial',
        cep: '60.150-160',
        logradouro: 'Avenida Santos Dumont',
        numero: '1000',
        complemento: 'Sala 302',
        bairro: 'Aldeota',
        cidade: 'Fortaleza',
        estado: 'CE',
        ponto_referencia: 'Em frente ao shopping'
      }
    end

    it 'cria o cliente e o endereço associado com sucesso' do
      result = described_class.call(
        empresa: empresa,
        nome: 'Guimarães Rosa',
        email: 'rosa@sertao.com',
        endereco: endereco_params
      )

      expect(result).to be_success
      cliente = result.data[:cliente]
      endereco = result.data[:endereco]

      expect(cliente).to be_persisted
      expect(endereco).to be_persisted
      expect(endereco.cliente).to eq(cliente)
      expect(endereco.cep).to eq('60150160') # sanitizado
      expect(endereco.logradouro).to eq('Avenida Santos Dumont')
      expect(endereco.cidade).to eq('Fortaleza')
      expect(endereco.estado).to eq('CE')
      # Primeiro endereço do cliente torna-se padrão automaticamente
      expect(endereco.padrao).to be true
      expect(result.data[:endereco_padrao]).to eq(endereco)
    end

    it 'permite especificar explicitamente que o endereço não deve ser padrão se padrao: false' do
      result = described_class.call(
        empresa: empresa,
        nome: 'Cecília Meireles',
        endereco: endereco_params.merge(padrao: false)
      )

      expect(result).to be_success
      endereco = result.data[:endereco]
      expect(endereco.padrao).to be false
      expect(result.data[:endereco_padrao]).to be_nil
    end

    it 'reverte a criação do cliente caso os dados do endereço sejam inválidos (rollback transacional)' do
      expect {
        result = described_class.call(
          empresa: empresa,
          nome: 'Rachel de Queiroz',
          endereco: endereco_params.merge(cep: '123') # CEP inválido (deve ter 8 dígitos)
        )

        expect(result).to be_failure
        expect(result.error_code).to eq(:record_invalid)
        expect(result.error).to include('Cep deve conter 8 dígitos numéricos')
      }.not_to change(Cliente, :count)

      expect(Endereco.count).to eq(0)
    end
  end

  describe 'atualização de cliente existente' do
    let!(:cliente) { create(:cliente, empresa: empresa, nome: 'Nome Original', telefone: '85900000000') }

    it 'atualiza atributos do cliente passando a instância de Cliente' do
      result = described_class.call(
        empresa: empresa,
        cliente: cliente,
        nome: 'Nome Atualizado',
        telefone: '85911111111'
      )

      expect(result).to be_success
      cliente.reload
      expect(cliente.nome).to eq('Nome Atualizado')
      expect(cliente.telefone).to eq('85911111111')
    end

    it 'atualiza atributos do cliente passando o ID numérico' do
      result = described_class.call(
        empresa: empresa,
        cliente: cliente.id,
        nome: 'Novo Nome por ID'
      )

      expect(result).to be_success
      expect(cliente.reload.nome).to eq('Novo Nome por ID')
    end
  end

  describe 'gestão de endereços em cliente existente' do
    let!(:cliente) { create(:cliente, empresa: empresa) }
    let!(:endereco_antigo) do
      create(
        :endereco,
        cliente: cliente,
        logradouro: 'Rua Antiga',
        padrao: true
      )
    end

    it 'adiciona um novo endereço como padrão desmarcando o anterior sem erro de unicidade' do
      expect(cliente.endereco_padrao).to eq(endereco_antigo)

      result = described_class.call(
        empresa: empresa,
        cliente: cliente,
        endereco: {
          titulo: 'Novo Endereço',
          cep: '60000000',
          logradouro: 'Rua Nova',
          numero: '500',
          bairro: 'Meireles',
          cidade: 'Fortaleza',
          estado: 'CE',
          padrao: true
        }
      )

      expect(result).to be_success
      novo_endereco = result.data[:endereco]
      expect(novo_endereco.padrao).to be true

      endereco_antigo.reload
      expect(endereco_antigo.padrao).to be false
      expect(cliente.reload.endereco_padrao).to eq(novo_endereco)
    end

    it 'adiciona um novo endereço secundário mantendo o padrão inalterado' do
      result = described_class.call(
        empresa: empresa,
        cliente: cliente,
        endereco: {
          titulo: 'Trabalho',
          cep: '60000000',
          logradouro: 'Rua Comercial',
          numero: '100',
          bairro: 'Centro',
          cidade: 'Fortaleza',
          estado: 'CE',
          padrao: false
        }
      )

      expect(result).to be_success
      novo_endereco = result.data[:endereco]
      expect(novo_endereco.padrao).to be false
      expect(endereco_antigo.reload.padrao).to be true
      expect(cliente.reload.endereco_padrao).to eq(endereco_antigo)
    end

    it 'atualiza um endereço existente fornecendo seu id' do
      result = described_class.call(
        empresa: empresa,
        cliente: cliente,
        endereco: {
          id: endereco_antigo.id,
          logradouro: 'Rua Antiga Reformada',
          numero: '999'
        }
      )

      expect(result).to be_success
      endereco_antigo.reload
      expect(endereco_antigo.logradouro).to eq('Rua Antiga Reformada')
      expect(endereco_antigo.numero).to eq('999')
    end

    it 'aceita uma instância existente de Endereco' do
      novo_end = build(
        :endereco,
        cliente: nil,
        logradouro: 'Rua Instância',
        padrao: true
      )

      result = described_class.call(
        empresa: empresa,
        cliente: cliente,
        endereco: novo_end
      )

      expect(result).to be_success
      expect(novo_end).to be_persisted
      expect(novo_end.cliente).to eq(cliente)
      expect(novo_end.padrao).to be true
      expect(endereco_antigo.reload.padrao).to be false
    end

    it 'falha com :unauthorized_address ao tentar associar uma instância de Endereço de outro cliente' do
      outro_cliente = create(:cliente, empresa: empresa, documento: '99988877701')
      endereco_outro_cliente = create(:endereco, cliente: outro_cliente)

      result = described_class.call(
        empresa: empresa,
        cliente: cliente,
        endereco: endereco_outro_cliente
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:unauthorized_address)
      expect(result.error).to include("Endereço informado pertence a outro cliente")
    end

    it 'falha com :unauthorized_address ao tentar atualizar endereço de outro cliente por ID' do
      outro_cliente = create(:cliente, empresa: empresa, documento: '99988877702')
      endereco_outro_cliente = create(:endereco, cliente: outro_cliente)

      result = described_class.call(
        empresa: empresa,
        cliente: cliente,
        endereco: {
          id: endereco_outro_cliente.id,
          logradouro: 'Invasão de Endereço'
        }
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:unauthorized_address)
    end

    it 'falha com :address_not_found quando o ID do endereço não existe' do
      result = described_class.call(
        empresa: empresa,
        cliente: cliente,
        endereco: {
          id: 999_999,
          logradouro: 'Inexistente'
        }
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:address_not_found)
    end

    it 'falha com :invalid_address_operation ao tentar passar ID de endereço existente na criação de novo cliente' do
      endereco_existente = create(:endereco)

      result = described_class.call(
        empresa: empresa,
        nome: 'Novo Cliente',
        endereco: {
          id: endereco_existente.id,
          logradouro: 'Tentativa Inválida'
        }
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:invalid_address_operation)
    end
  end

  describe 'isolamento multi-tenant' do
    let(:cliente_outra_empresa) { create(:cliente, empresa: outra_empresa) }

    it 'falha se a empresa não for informada (:tenant_not_found)' do
      result = described_class.call(empresa: nil, nome: 'Teste')
      expect(result).to be_failure
      expect(result.error_code).to eq(:tenant_not_found)
    end

    it 'falha se a empresa não existir (:tenant_not_found)' do
      result = described_class.call(empresa: 999_999, nome: 'Teste')
      expect(result).to be_failure
      expect(result.error_code).to eq(:tenant_not_found)
    end

    it 'falha ao tentar atualizar cliente de outra empresa (:unauthorized_tenant)' do
      result = described_class.call(
        empresa: empresa,
        cliente: cliente_outra_empresa,
        nome: 'Tentativa Hacker'
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:unauthorized_tenant)
    end

    it 'falha ao tentar atualizar cliente de outra empresa por ID (:unauthorized_tenant)' do
      result = described_class.call(
        empresa: empresa,
        cliente: cliente_outra_empresa.id,
        nome: 'Tentativa Hacker'
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:unauthorized_tenant)
    end

    it 'falha se o ID do cliente não existir em nenhuma empresa (:client_not_found)' do
      result = described_class.call(
        empresa: empresa,
        cliente: 999_999,
        nome: 'Inexistente'
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:client_not_found)
    end

    it 'permite cadastrar cliente com mesmo documento em empresas diferentes' do
      create(:cliente, empresa: outra_empresa, documento: '12345678901')

      result = described_class.call(
        empresa: empresa,
        nome: 'Cliente na Empresa A',
        documento: '123.456.789-01'
      )

      expect(result).to be_success
      expect(result.data[:cliente].documento).to eq('12345678901')
    end
  end

  describe 'unicidade de documento e funcionalidade de upsert' do
    let!(:cliente_existente) do
      create(
        :cliente,
        empresa: empresa,
        nome: 'Cliente Original',
        documento: '12345678901',
        telefone: '85988880000'
      )
    end

    it 'rejeita novo cadastro com documento já existente na mesma empresa (:document_already_exists)' do
      result = described_class.call(
        empresa: empresa,
        nome: 'Outro Cliente',
        documento: '123.456.789-01'
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:document_already_exists)
      expect(result.error).to include('Já existe um cliente cadastrado com este documento')
    end

    it 'com upsert_por_documento: true, atualiza o cliente existente em vez de falhar' do
      result = described_class.call(
        empresa: empresa,
        nome: 'Cliente Atualizado Via Upsert',
        documento: '123.456.789-01',
        telefone: '85999991111',
        upsert_por_documento: true
      )

      expect(result).to be_success
      cliente = result.data[:cliente]
      expect(cliente.id).to eq(cliente_existente.id)
      expect(cliente.nome).to eq('Cliente Atualizado Via Upsert')
      expect(cliente.telefone).to eq('85999991111')
    end

    it 'rejeita alteração de documento para um já existente de outro cliente na mesma empresa (:document_already_exists)' do
      outro_cliente = create(:cliente, empresa: empresa, documento: '99988877766')

      result = described_class.call(
        empresa: empresa,
        cliente: outro_cliente,
        documento: '123.456.789-01' # documento que pertence ao cliente_existente
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:document_already_exists)
    end

    it 'permite salvar o mesmo cliente mantendo seu próprio documento' do
      result = described_class.call(
        empresa: empresa,
        cliente: cliente_existente,
        nome: 'Novo Nome',
        documento: '123.456.789-01'
      )

      expect(result).to be_success
      expect(cliente_existente.reload.nome).to eq('Novo Nome')
    end
  end

  describe 'validações de modelo (:record_invalid)' do
    it 'falha se o nome for nulo' do
      result = described_class.call(
        empresa: empresa,
        nome: nil
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:record_invalid)
      expect(result.error).to match(/Nome (can't be blank|não pode ficar em branco)/i)
    end

    it 'falha se o email tiver formato inválido' do
      result = described_class.call(
        empresa: empresa,
        nome: 'Cliente Teste',
        email: 'email_invalido_sem_arroba'
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:record_invalid)
      expect(result.error).to match(/Email (is invalid|não é válido)/i)
    end
  end
end
