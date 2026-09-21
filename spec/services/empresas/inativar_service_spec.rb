# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Empresas::InativarService, type: :service do
  let!(:empresa) { create(:empresa, ativo: true) }

  describe 'inativação de empresa ativa' do
    it 'inativa a empresa com sucesso passando a instância via kwargs' do
      result = described_class.call(
        empresa: empresa,
        motivo: 'Inadimplência financeira'
      )

      expect(result).to be_success
      expect(result.data[:inativado]).to be true
      expect(result.data[:motivo]).to eq('Inadimplência financeira')
      expect(empresa.reload.ativo).to be false
    end

    it 'inativa a empresa passando como primeiro argumento posicional' do
      result = described_class.call(empresa, motivo: 'Cancelamento contratual')

      expect(result).to be_success
      expect(result.data[:inativado]).to be true
      expect(empresa.reload.ativo).to be false
    end

    it 'inativa a empresa passando o ID numérico' do
      result = described_class.call(empresa: empresa.id)

      expect(result).to be_success
      expect(empresa.reload.ativo).to be false
    end

    it 'inativa a empresa passando ID em string' do
      result = described_class.call(empresa: empresa.id.to_s)

      expect(result).to be_success
      expect(empresa.reload.ativo).to be false
    end

    it 'inativa a empresa passando o slug' do
      result = described_class.call(empresa: empresa.slug)

      expect(result).to be_success
      expect(empresa.reload.ativo).to be false
    end
  end

  describe 'tratamento de assinaturas vinculadas' do
    let(:plano) { create(:plano) }
    let!(:assinatura_ativa) { create(:assinatura, empresa: empresa, plano: plano, status: :ativa) }

    it 'preserva o status da assinatura por padrão' do
      result = described_class.call(empresa: empresa)

      expect(result).to be_success
      expect(assinatura_ativa.reload.status).to eq('ativa')
      expect(result.data[:assinaturas_suspensas]).to eq(0)
    end

    it 'suspende assinaturas ativas quando suspender_assinaturas: true' do
      result = described_class.call(
        empresa: empresa,
        suspender_assinaturas: true
      )

      expect(result).to be_success
      expect(result.data[:assinaturas_suspensas]).to eq(1)
      expect(assinatura_ativa.reload.status).to eq('suspensa')
    end

    it 'cancela assinaturas vinculadas quando cancelar_assinaturas: true' do
      result = described_class.call(
        empresa: empresa,
        cancelar_assinaturas: true
      )

      expect(result).to be_success
      expect(result.data[:assinaturas_canceladas]).to eq(1)
      expect(assinatura_ativa.reload.status).to eq('cancelada')
    end
  end

  describe 'idempotência e empresa já inativa' do
    let!(:empresa_inativa) { create(:empresa, ativo: false) }

    it 'retorna erro quando a empresa já está inativa e ignorar_se_inativo é false' do
      result = described_class.call(empresa: empresa_inativa)

      expect(result).to be_failure
      expect(result.error_code).to eq(:empresa_already_inactive)
      expect(result.error).to include('Empresa já se encontra inativa')
    end

    it 'retorna sucesso idempotente quando ignorar_se_inativo é true' do
      result = described_class.call(
        empresa: empresa_inativa,
        ignorar_se_inativo: true,
        motivo: 'Verificação periódica'
      )

      expect(result).to be_success
      expect(result.data[:inativado]).to be false
      expect(result.data[:ja_estava_inativo]).to be true
      expect(empresa_inativa.reload.ativo).to be false
    end
  end

  describe 'validação de empresa não encontrada' do
    it 'retorna erro tenant_not_found quando a empresa não for informada' do
      result = described_class.call(empresa: nil)

      expect(result).to be_failure
      expect(result.error_code).to eq(:tenant_not_found)
      expect(result.error).to eq('Empresa não informada ou não encontrada')
    end

    it 'retorna erro tenant_not_found quando a empresa não existir' do
      result = described_class.call(empresa: 999_999_999)

      expect(result).to be_failure
      expect(result.error_code).to eq(:tenant_not_found)
      expect(result.error).to eq('Empresa não informada ou não encontrada')
    end
  end

  describe 'alias' do
    it 'permite chamar o serviço através de Empresas::DesativarService' do
      result = Empresas::DesativarService.call(
        empresa: empresa,
        motivo: 'Inativação via alias'
      )

      expect(result).to be_success
      expect(empresa.reload.ativo).to be false
    end
  end
end
