package br.com.postlymail.service;

import br.com.postlymail.model.Venda;
import br.com.postlymail.model.ItemVenda;
import br.com.postlymail.model.Produto;
import br.com.postlymail.util.HibernateUtil;
import jakarta.persistence.EntityManager;
import jakarta.persistence.EntityTransaction;
import java.util.List;

public class VendaService {

    public List<Venda> listarTodas() {
        try (EntityManager em = HibernateUtil.getEntityManager()) {
            return em.createQuery("SELECT DISTINCT v FROM Venda v JOIN FETCH v.cliente JOIN FETCH v.itens i JOIN FETCH i.produto", Venda.class).getResultList();
        }
    }

    public void salvarVenda(Venda venda) {
        EntityManager em = HibernateUtil.getEntityManager();
        EntityTransaction transaction = em.getTransaction();
        try {
            transaction.begin();
            
            if (venda.getId() != null) {
                // UPDATE logic: Rollback old items stock first
                Venda vendaAntiga = em.find(Venda.class, venda.getId());
                for (ItemVenda itemOld : vendaAntiga.getItens()) {
                    Produto p = em.find(Produto.class, itemOld.getProduto().getId());
                    if (p != null) {
                        p.setEstoque(p.getEstoque() + itemOld.getQuantidade());
                        em.merge(p);
                    }
                }
                // Clear old items to avoid duplicates if items changed
                vendaAntiga.getItens().clear();
                em.flush();
                
                // Update basic data
                vendaAntiga.setCliente(em.merge(venda.getCliente()));
                vendaAntiga.setValorTotal(venda.getValorTotal());
                vendaAntiga.setDataVenda(venda.getDataVenda());
                
                // Add new items and reduce stock
                for (ItemVenda itemNew : venda.getItens()) {
                    itemNew.setVenda(vendaAntiga);
                    vendaAntiga.getItens().add(itemNew);
                    
                    Produto p = em.find(Produto.class, itemNew.getProduto().getId());
                    if (p.getEstoque() < itemNew.getQuantidade()) {
                        throw new RuntimeException("Estoque insuficiente para " + p.getNome());
                    }
                    p.setEstoque(p.getEstoque() - itemNew.getQuantidade());
                    em.merge(p);
                }
                em.merge(vendaAntiga);
            } else {
                // NEW SALE logic
                em.persist(venda);
                for (ItemVenda item : venda.getItens()) {
                    Produto produto = em.find(Produto.class, item.getProduto().getId());
                    if (produto != null && produto.getEstoque() != null) {
                        int novoEstoque = produto.getEstoque() - item.getQuantidade();
                        if (novoEstoque < 0) {
                            throw new RuntimeException("Estoque insuficiente para: " + produto.getNome());
                        }
                        produto.setEstoque(novoEstoque);
                        em.merge(produto);
                    }
                }
            }
            
            transaction.commit();
        } catch (Exception e) {
            if (transaction.isActive()) {
                transaction.rollback();
            }
            throw e;
        } finally {
            em.close();
        }
    }

    public void excluir(Long id) {
        EntityManager em = HibernateUtil.getEntityManager();
        EntityTransaction transaction = em.getTransaction();
        try {
            transaction.begin();
            Venda venda = em.find(Venda.class, id);
            if (venda != null) {
                // When deleting a sale, should we return items to stock? 
                // In most CRMs, yes. Let's do it for completeness.
                for (ItemVenda item : venda.getItens()) {
                    Produto produto = em.find(Produto.class, item.getProduto().getId());
                    if (produto != null && produto.getEstoque() != null) {
                        produto.setEstoque(produto.getEstoque() + item.getQuantidade());
                        em.merge(produto);
                    }
                }
                em.remove(venda);
            }
            transaction.commit();
        } catch (Exception e) {
            if (transaction.isActive()) {
                transaction.rollback();
            }
            throw e;
        } finally {
            em.close();
        }
    }
}
