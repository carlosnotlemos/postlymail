# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Campanhas::DuplicarService, type: :service do
  let!(:empresa) { create(:empresa, slug: 'clone-store', ativo: true) }
  let!(:campanha_origem) do
    create(
      :campanha,
      empresa: empresa,
      nome: 'Campanha Original',
      canal: :email,
      assunto: 'Assunto Original',
      conteudo: '<p>Conteudo Original</p>',
      url_midia: 'https://exemplo.com/banner.png',
      segmento: :com_compras,
      status: :concluida,
      data_envio: 1.day.ago
    )
  end

  describe '.call' do
    context 'quando clonando com sucesso' do
      it 'cria nova campanha em rascunho com conteúdo duplicado' do
        resultado = described_class.call(campanha: campanha_origem)

        expect(resultado).to be_success
        nova = resultado.data[:campanha]
        expect(nova).to be_persisted
        expect(nova.id).not_to eq(campanha_origem.id)
        expect(nova.empresa).to eq(empresa)
        expect(nova.nome).to eq('Campanha Original (Cópia)')
        expect(nova.canal).to eq(campanha_origem.canal)
        expect(nova.assunto).to eq(campanha_origem.assunto)
        expect(nova.conteudo).to eq(campanha_origem.conteudo)
        expect(nova.url_midia).to eq(campanha_origem.url_midia)
        expect(nova.segmento).to eq(campanha_origem.segmento)
        expect(nova.status).to eq('rascunho')
        expect(nova.data_envio).to be_nil
      end

      it 'permite especificar um nome customizado para a cópia' do
        resultado = described_class.call(
          campanha: campanha_origem,
          nome: 'Campanha Nova Versão'
        )

        expect(resultado).to be_success
        expect(resultado.data[:campanha].nome).to eq('Campanha Nova Versão')
      end

      it 'permite resolver a campanha por ID' do
        resultado = described_class.call(campanha: campanha_origem.id)

        expect(resultado).to be_success
        expect(resultado.data[:campanha]).to be_persisted
      end
    end

    context 'validações e erros' do
      it 'falha quando campanha não existe' do
        resultado = described_class.call(campanha: 999_999)

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:campaign_not_found)
      end

      it 'falha quando a campanha pertence a outra empresa' do
        outra_empresa = create(:empresa)

        resultado = described_class.call(
          campanha: campanha_origem,
          empresa: outra_empresa
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:unauthorized_tenant)
      end

      it 'falha quando a empresa está inativa' do
        empresa.update!(ativo: false)

        resultado = described_class.call(campanha: campanha_origem)

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:empresa_inactive)
      end
    end

    context 'aliases' do
      it 'funciona através de Campanhas::ClonarService' do
        resultado = Campanhas::ClonarService.call(campanha: campanha_origem)
        expect(resultado).to be_success
        expect(resultado.data[:campanha]).to be_persisted
      end
    end
  end
end
