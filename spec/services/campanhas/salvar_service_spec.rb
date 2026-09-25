# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Campanhas::SalvarService, type: :service do
  let!(:empresa) { create(:empresa, slug: 'drop-store', ativo: true) }

  describe '.call' do
    context 'ao criar uma nova campanha' do
      it 'cria com sucesso uma campanha de e-mail' do
        resultado = described_class.call(
          empresa: empresa,
          nome: 'Black Friday 2026',
          canal: :email,
          assunto: 'Descontos imperdíveis!',
          conteudo: '<h1>Aproveite até 50% OFF</h1>',
          segmento: :todos
        )

        expect(resultado).to be_success
        campanha = resultado.data[:campanha]
        expect(campanha).to be_persisted
        expect(campanha.nome).to eq('Black Friday 2026')
        expect(campanha.canal).to eq('email')
        expect(campanha.assunto).to eq('Descontos imperdíveis!')
        expect(campanha.conteudo).to eq('<h1>Aproveite até 50% OFF</h1>')
        expect(campanha.segmento).to eq('todos')
        expect(campanha.status).to eq('rascunho')
        expect(resultado.data[:criado]).to be true
      end

      it 'cria com sucesso uma campanha de whatsapp sem exigir assunto' do
        resultado = described_class.call(
          empresa: empresa,
          nome: 'Lembrete WhatsApp',
          canal: :whatsapp,
          conteudo: 'Olá! Não se esqueça do carrinho abandonado.',
          segmento: :com_compras
        )

        expect(resultado).to be_success
        campanha = resultado.data[:campanha]
        expect(campanha).to be_persisted
        expect(campanha.canal).to eq('whatsapp')
        expect(campanha.assunto).to be_nil
        expect(campanha.segmento).to eq('com_compras')
      end

      it 'permite criar campanha agendada com data_envio futura' do
        data_futura = 2.days.from_now
        resultado = described_class.call(
          empresa: empresa,
          nome: 'Campanha Agendada',
          canal: :email,
          assunto: 'Novidades',
          conteudo: 'Texto',
          status: :agendada,
          data_envio: data_futura
        )

        expect(resultado).to be_success
        campanha = resultado.data[:campanha]
        expect(campanha.agendada?).to be true
        expect(campanha.data_envio).to be_within(2.seconds).of(data_futura)
      end

      it 'resolve empresa polimorficamente por slug ou id' do
        resultado = described_class.call(
          empresa: 'drop-store',
          nome: 'Campanha por Slug',
          canal: :email,
          assunto: 'Assunto',
          conteudo: 'Conteúdo'
        )

        expect(resultado).to be_success
        expect(resultado.data[:campanha].empresa).to eq(empresa)
      end
    end

    context 'ao atualizar uma campanha existente' do
      let!(:campanha) { create(:campanha, empresa: empresa, nome: 'Nome Antigo', status: :rascunho) }

      it 'atualiza com sucesso os atributos' do
        resultado = described_class.call(
          campanha: campanha,
          nome: 'Nome Atualizado',
          assunto: 'Novo Assunto'
        )

        expect(resultado).to be_success
        expect(resultado.data[:atualizado]).to be true
        campanha.reload
        expect(campanha.nome).to eq('Nome Atualizado')
        expect(campanha.assunto).to eq('Novo Assunto')
      end

      it 'permite resolver a campanha por ID numérico' do
        resultado = described_class.call(
          campanha: campanha.id,
          nome: 'Nome Atualizado por ID'
        )

        expect(resultado).to be_success
        expect(campanha.reload.nome).to eq('Nome Atualizado por ID')
      end
    end

    context 'validações e casos de erro' do
      it 'falha quando empresa não é informada' do
        resultado = described_class.call(
          nome: 'Campanha sem empresa',
          canal: :email,
          conteudo: 'Teste'
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:tenant_not_found)
      end

      it 'falha quando a empresa está inativa' do
        empresa.update!(ativo: false)

        resultado = described_class.call(
          empresa: empresa,
          nome: 'Campanha com empresa inativa',
          canal: :email,
          assunto: 'Assunto',
          conteudo: 'Conteudo'
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:empresa_inactive)
      end

      it 'falha quando campanha pertence a outra empresa' do
        outra_empresa = create(:empresa)
        campanha_outra = create(:campanha, empresa: outra_empresa)

        resultado = described_class.call(
          empresa: empresa,
          campanha: campanha_outra,
          nome: 'Tentativa de alteração'
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:unauthorized_tenant)
      end

      it 'falha quando canal é email e o assunto não é informado' do
        resultado = described_class.call(
          empresa: empresa,
          nome: 'Email sem assunto',
          canal: :email,
          assunto: nil,
          conteudo: 'Conteúdo'
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:email_subject_required)
      end

      it 'falha quando status é agendada e data_envio não é informada' do
        resultado = described_class.call(
          empresa: empresa,
          nome: 'Agendada sem data',
          canal: :whatsapp,
          conteudo: 'Conteúdo',
          status: :agendada,
          data_envio: nil
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:scheduled_date_required)
      end

      it 'falha quando status é agendada e data_envio está no passado' do
        resultado = described_class.call(
          empresa: empresa,
          nome: 'Agendada no passado',
          canal: :whatsapp,
          conteudo: 'Conteúdo',
          status: :agendada,
          data_envio: 1.hour.ago
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:scheduled_date_in_the_past)
      end

      it 'falha quando tanto conteudo quanto url_midia estão vazios' do
        resultado = described_class.call(
          empresa: empresa,
          nome: 'Campanha sem conteúdo e sem mídia',
          canal: :whatsapp,
          conteudo: nil,
          url_midia: nil
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:empty_content)
      end

      it 'permite criar campanha informando apenas url_midia sem conteudo textual' do
        resultado = described_class.call(
          empresa: empresa,
          nome: 'Banner WhatsApp',
          canal: :whatsapp,
          conteudo: nil,
          url_midia: 'https://exemplo.com/banner.jpg'
        )

        expect(resultado).to be_success
        expect(resultado.data[:campanha]).to be_persisted
        expect(resultado.data[:campanha].url_midia).to eq('https://exemplo.com/banner.jpg')
      end

      it 'prioriza a busca da campanha no escopo da empresa ao resolver por ID' do
        campanha = create(:campanha, empresa: empresa, nome: 'Original')

        expect(empresa.campanhas).to receive(:find_by).with(id: campanha.id).and_call_original

        resultado = described_class.call(
          empresa: empresa,
          campanha: campanha.id,
          nome: 'Nome Atualizado'
        )

        expect(resultado).to be_success
        expect(resultado.data[:campanha].nome).to eq('Nome Atualizado')
      end

      it 'falha ao tentar modificar uma campanha já concluída' do
        campanha_concluida = create(:campanha, empresa: empresa, status: :concluida)

        resultado = described_class.call(
          campanha: campanha_concluida,
          nome: 'Modificando concluída'
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:cannot_modify_completed_campaign)
      end

      it 'falha ao tentar modificar uma campanha cancelada' do
        campanha_cancelada = create(:campanha, empresa: empresa, status: :cancelada)

        resultado = described_class.call(
          campanha: campanha_cancelada,
          nome: 'Modificando cancelada'
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:cannot_modify_cancelled_campaign)
      end

      it 'falha ao tentar modificar uma campanha que está enviando' do
        campanha_enviando = create(:campanha, empresa: empresa, status: :enviando)

        resultado = described_class.call(
          campanha: campanha_enviando,
          nome: 'Modificando enviando'
        )

        expect(resultado).to be_failure
        expect(resultado.error_code).to eq(:cannot_modify_sending_campaign)
      end
    end

    context 'aliases' do
      it 'funciona através de Campanhas::CriarService e AtualizarService' do
        res1 = Campanhas::CriarService.call(
          empresa: empresa,
          nome: 'Alias Criar',
          canal: :whatsapp,
          conteudo: 'Msg'
        )
        expect(res1).to be_success

        res2 = Campanhas::AtualizarService.call(
          campanha: res1.data[:campanha],
          nome: 'Alias Atualizar'
        )
        expect(res2).to be_success
        expect(res1.data[:campanha].reload.nome).to eq('Alias Atualizar')
      end
    end
  end
end
