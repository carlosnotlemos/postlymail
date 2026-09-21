require 'rails_helper'

RSpec.describe Clientes::ResolverEnderecoService, type: :service do
  let(:empresa) { create(:empresa) }
  let(:outra_empresa) { create(:empresa) }
  let(:cliente) { create(:cliente, empresa: empresa, nome: 'Machado de Assis', telefone: '21999998888') }

  let!(:endereco_padrao) do
    create(
      :endereco,
      cliente: cliente,
      titulo: 'Casa Principal',
      cep: '20000000',
      logradouro: 'Rua do Ouvidor',
      numero: '100',
      complemento: 'Sobrado',
      bairro: 'Centro',
      cidade: 'Rio de Janeiro',
      estado: 'RJ',
      padrao: true
    )
  end

  let!(:endereco_secundario) do
    create(
      :endereco,
      cliente: cliente,
      titulo: 'Escritório',
      cep: '22000000',
      logradouro: 'Avenida Atlântica',
      numero: '500',
      complemento: nil,
      bairro: 'Copacabana',
      cidade: 'Rio de Janeiro',
      estado: 'RJ',
      padrao: false
    )
  end

  describe 'alias do serviço' do
    it 'permite chamada através de Clientes::ResolverEnderecoEntregaService' do
      expect(Clientes::ResolverEnderecoEntregaService).to eq(Clientes::ResolverEnderecoService)
      result = Clientes::ResolverEnderecoEntregaService.call(
        empresa: empresa,
        cliente: cliente
      )
      expect(result).to be_success
      expect(result.data[:endereco]).to eq(endereco_padrao)
    end
  end

  describe 'resolução automática de endereço' do
    it 'seleciona o endereço padrão automaticamente quando nenhum é informado' do
      result = described_class.call(
        empresa: empresa,
        cliente: cliente
      )

      expect(result).to be_success
      expect(result.data[:endereco]).to eq(endereco_padrao)
      expect(result.data[:snapshot]['endereco_id']).to eq(endereco_padrao.id)
      expect(result.data[:snapshot]['cep']).to eq('20000-000')
      expect(result.data[:snapshot]['destinatario']).to eq('Machado de Assis')
      expect(result.data[:snapshot]['telefone']).to eq('21999998888')
      expect(result.data[:texto_formatado]).to include('Rua do Ouvidor, 100')
      expect(result.data[:texto_formatado]).to include('CEP 20000-000')
    end

    it 'seleciona o endereço mais recente quando o cliente não tem nenhum marcado como padrão' do
      cliente.enderecos.update_all(padrao: false)

      result = described_class.call(
        empresa: empresa,
        cliente: cliente
      )

      expect(result).to be_success
      expect(result.data[:endereco]).to eq(endereco_secundario)
    end

    context 'quando o cliente não possui nenhum endereço cadastrado' do
      let(:cliente_sem_endereco) { create(:cliente, empresa: empresa, documento: '11122233344') }

      it 'falha com :address_not_found quando a entrega física for exigida' do
        result = described_class.call(
          empresa: empresa,
          cliente: cliente_sem_endereco,
          tipo_entrega: :correios_pac
        )

        expect(result).to be_failure
        expect(result.error_code).to eq(:address_not_found)
        expect(result.error).to include('Cliente não possui nenhum endereço cadastrado')
      end

      it 'sucede quando o tipo de entrega for retirada na loja' do
        result = described_class.call(
          empresa: empresa,
          cliente: cliente_sem_endereco,
          tipo_entrega: :retirada
        )

        expect(result).to be_success
        expect(result.data[:endereco]).to be_nil
        expect(result.data[:snapshot]['tipo_entrega']).to eq('retirada')
        expect(result.data[:snapshot]['retirada_na_loja']).to be true
        expect(result.data[:snapshot]['texto_formatado']).to eq('Retirada no balcão / loja física')
      end
    end
  end

  describe 'resolução com endereço específico informado' do
    it 'seleciona o endereço informado por ID numérico' do
      result = described_class.call(
        empresa: empresa,
        cliente: cliente,
        endereco: endereco_secundario.id
      )

      expect(result).to be_success
      expect(result.data[:endereco]).to eq(endereco_secundario)
      expect(result.data[:snapshot]['titulo']).to eq('Escritório')
    end

    it 'seleciona o endereço informado por instância de Endereco' do
      result = described_class.call(
        empresa: empresa,
        cliente: cliente,
        endereco: endereco_secundario
      )

      expect(result).to be_success
      expect(result.data[:endereco]).to eq(endereco_secundario)
    end

    it 'seleciona o endereço informado através de Hash com chave :id' do
      result = described_class.call(
        empresa: empresa,
        cliente: cliente,
        endereco: { id: endereco_secundario.id }
      )

      expect(result).to be_success
      expect(result.data[:endereco]).to eq(endereco_secundario)
    end

    it 'permite sobrescrever destinatário e telefone no snapshot' do
      result = described_class.call(
        empresa: empresa,
        cliente: cliente,
        destinatario: 'Carolina Augusta',
        telefone: '21988887777'
      )

      expect(result).to be_success
      expect(result.data[:snapshot]['destinatario']).to eq('Carolina Augusta')
      expect(result.data[:snapshot]['telefone']).to eq('21988887777')
    end
  end

  describe 'validações e isolamento multi-tenant' do
    it 'falha se empresa for nula (:tenant_not_found)' do
      result = described_class.call(
        empresa: nil,
        cliente: cliente
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:tenant_not_found)
    end

    it 'falha se empresa não existir (:tenant_not_found)' do
      result = described_class.call(
        empresa: 999_999,
        cliente: cliente
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:tenant_not_found)
    end

    it 'falha se cliente for nulo (:client_not_found)' do
      result = described_class.call(
        empresa: empresa,
        cliente: nil
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:client_not_found)
    end

    it 'falha se cliente pertencer a outra empresa (:unauthorized_tenant)' do
      cliente_outro_tenant = create(:cliente, empresa: outra_empresa, documento: '88877766655')

      result = described_class.call(
        empresa: empresa,
        cliente: cliente_outro_tenant
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:unauthorized_tenant)
    end

    it 'falha se endereço pertencer a outro cliente (:unauthorized_address)' do
      outro_cliente = create(:cliente, empresa: empresa, documento: '55544433322')
      endereco_outro_cliente = create(:endereco, cliente: outro_cliente)

      result = described_class.call(
        empresa: empresa,
        cliente: cliente,
        endereco: endereco_outro_cliente
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:unauthorized_address)
    end

    it 'falha se o ID do endereço não existir (:address_not_found)' do
      result = described_class.call(
        empresa: empresa,
        cliente: cliente,
        endereco: 999_999
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:address_not_found)
    end

    it 'falha se o tipo de entrega for inválido (:invalid_delivery_type)' do
      result = described_class.call(
        empresa: empresa,
        cliente: cliente,
        tipo_entrega: :teletransporte
      )

      expect(result).to be_failure
      expect(result.error_code).to eq(:invalid_delivery_type)
    end
  end

  describe 'tipos de entrega suportados' do
    %i[retirada motoboy_uber correios_pac correios_sedex].each do |tipo|
      it "aceita o tipo de entrega :#{tipo}" do
        result = described_class.call(
          empresa: empresa,
          cliente: cliente,
          tipo_entrega: tipo
        )

        expect(result).to be_success
        expect(result.data[:tipo_entrega]).to eq(tipo.to_s)
        expect(result.data[:snapshot]['tipo_entrega']).to eq(tipo.to_s)
      end
    end

    it 'aceita tipo_entrega como inteiro correspondente ao enum do model Venda' do
      # enum :tipo_entrega, { retirada: 0, motoboy_uber: 1, correios_pac: 2, correios_sedex: 3 }
      result = described_class.call(
        empresa: empresa,
        cliente: cliente,
        tipo_entrega: 2
      )

      expect(result).to be_success
      expect(result.data[:tipo_entrega]).to eq('correios_pac')
    end
  end
end
