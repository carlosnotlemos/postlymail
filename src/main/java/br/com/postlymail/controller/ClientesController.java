package br.com.postlymail.controller;

import br.com.postlymail.model.Cliente;
import br.com.postlymail.service.ClienteService;
import javafx.collections.FXCollections;
import javafx.collections.ObservableList;
import javafx.event.ActionEvent;
import javafx.fxml.FXML;
import javafx.fxml.FXMLLoader;
import javafx.scene.Scene;
import javafx.scene.control.*;
import javafx.scene.control.cell.PropertyValueFactory;
import javafx.stage.Modality;
import javafx.stage.Stage;
import javafx.stage.StageStyle;
import javafx.scene.layout.HBox;
import javafx.concurrent.Task;
import java.io.IOException;
import java.util.List;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;

public class ClientesController {

    @FXML private TableView<Cliente> tableClientes;
    @FXML private TableColumn<Cliente, String> colNome;
    @FXML private TableColumn<Cliente, String> colEmail;
    @FXML private TableColumn<Cliente, String> colTelefone;
    @FXML private TableColumn<Cliente, LocalDateTime> colCadastro;
    @FXML private TableColumn<Cliente, Void> colAcoes;
    @FXML private ProgressIndicator progressLoading;

    @FXML private Label lblTitulo;
    @FXML private TextField txtNome;
    @FXML private TextField txtEmail;
    @FXML private TextField txtTelefone;

    private final ClienteService clienteService = new ClienteService();
    private final ObservableList<Cliente> observableClientes = FXCollections.observableArrayList();
    private Cliente clienteEmEdicao;

    @FXML
    public void initialize() {
        configurarTabela();
        configurarAcoes();
        carregarClientes();
    }

    private void configurarTabela() {
        colNome.setCellValueFactory(new PropertyValueFactory<>("nome"));
        colEmail.setCellValueFactory(new PropertyValueFactory<>("email"));
        colTelefone.setCellValueFactory(new PropertyValueFactory<>("telefone"));
        
        // Formatar data
        DateTimeFormatter formatter = DateTimeFormatter.ofPattern("dd/MM/yyyy HH:mm");
        colCadastro.setCellValueFactory(new PropertyValueFactory<>("dataCadastro"));
        colCadastro.setCellFactory(column -> new TableCell<>() {
            @Override
            protected void updateItem(LocalDateTime item, boolean empty) {
                super.updateItem(item, empty);
                if (empty || item == null) {
                    setText(null);
                } else {
                    setText(item.format(formatter));
                }
            }
        });

        tableClientes.setItems(observableClientes);
    }

    private void configurarAcoes() {
        colAcoes.setCellFactory(column -> new TableCell<>() {
            private final Button btnEdit = new Button("✎");
            private final Button btnDelete = new Button("🗑");
            private final HBox container = new HBox(10, btnEdit, btnDelete);

            {
                btnEdit.getStyleClass().add("button-action-edit");
                btnDelete.getStyleClass().add("button-action-delete");
                btnEdit.setTooltip(new Tooltip("Editar"));
                btnDelete.setTooltip(new Tooltip("Excluir"));

                btnEdit.setOnAction(event -> {
                    Cliente cliente = getTableView().getItems().get(getIndex());
                    handleEditarCliente(cliente);
                });

                btnDelete.setOnAction(event -> {
                    Cliente cliente = getTableView().getItems().get(getIndex());
                    handleExcluirCliente(cliente);
                });
            }

            @Override
            protected void updateItem(Void item, boolean empty) {
                super.updateItem(item, empty);
                if (empty) {
                    setGraphic(null);
                } else {
                    setGraphic(container);
                }
            }
        });
    }

    private void carregarClientes() {
        Task<List<Cliente>> loadTask = new Task<>() {
            @Override
            protected List<Cliente> call() {
                return clienteService.listarTodos();
            }
        };

        loadTask.setOnRunning(e -> progressLoading.setVisible(true));
        loadTask.setOnSucceeded(e -> {
            observableClientes.setAll(loadTask.getValue());
            progressLoading.setVisible(false);
        });
        loadTask.setOnFailed(e -> {
            progressLoading.setVisible(false);
            mostrarAlerta("Erro", "Falha ao carregar clientes: " + loadTask.getException().getMessage());
        });

        new Thread(loadTask).start();
    }

    @FXML
    private void handleNovoCliente(ActionEvent event) {
        clienteEmEdicao = null;
        showClienteForm(null);
    }

    private void handleEditarCliente(Cliente cliente) {
        clienteEmEdicao = cliente;
        showClienteForm(cliente);
    }

    private void handleExcluirCliente(Cliente cliente) {
        Alert alert = new Alert(Alert.AlertType.CONFIRMATION);
        alert.setTitle("Confirmar Exclusão");
        alert.setHeaderText("Excluir Cliente");
        alert.setContentText("Tem certeza que deseja excluir o cliente " + cliente.getNome() + "?");
        
        // Custom styling for dialog (basic)
        alert.initStyle(StageStyle.UTILITY);

        alert.showAndWait().ifPresent(response -> {
            if (response == ButtonType.OK) {
                try {
                    clienteService.excluir(cliente.getId());
                    carregarClientes();
                } catch (Exception e) {
                    mostrarAlerta("Erro", "Falha ao excluir cliente: " + e.getMessage());
                }
            }
        });
    }

    private void showClienteForm(Cliente cliente) {
        try {
            FXMLLoader loader = new FXMLLoader(getClass().getResource("/br/com/postlymail/view/ClienteFormView.fxml"));
            loader.setController(this);
            Scene scene = new Scene(loader.load());
            
            Stage dialogStage = new Stage();
            dialogStage.initModality(Modality.APPLICATION_MODAL);
            dialogStage.initStyle(StageStyle.UNDECORATED);
            dialogStage.setScene(scene);
            
            if (cliente != null) {
                lblTitulo.setText("Editar Cliente");
                txtNome.setText(cliente.getNome());
                txtEmail.setText(cliente.getEmail());
                txtTelefone.setText(cliente.getTelefone());
            } else {
                lblTitulo.setText("Novo Cliente");
                txtNome.clear();
                txtEmail.clear();
                txtTelefone.clear();
            }

            dialogStage.showAndWait();
        } catch (IOException e) {
            e.printStackTrace();
        }
    }

    @FXML
    private void handleSalvar(ActionEvent event) {
        if (txtNome.getText().isEmpty() || txtEmail.getText().isEmpty()) {
            mostrarAlerta("Erro", "Nome e E-mail são obrigatórios.");
            return;
        }

        if (!txtEmail.getText().matches("^[A-Za-z0-9+_.-]+@(.+)$")) {
            mostrarAlerta("Erro", "E-mail inválido.");
            return;
        }

        if (clienteEmEdicao == null) {
            clienteEmEdicao = new Cliente();
        }

        clienteEmEdicao.setNome(txtNome.getText());
        clienteEmEdicao.setEmail(txtEmail.getText());
        clienteEmEdicao.setTelefone(txtTelefone.getText());

        try {
            clienteService.salvar(clienteEmEdicao);
            carregarClientes();
            fecharModal(event);
        } catch (Exception e) {
            mostrarAlerta("Erro", "Falha ao salvar cliente: " + e.getMessage());
        }
    }

    @FXML
    private void handleCancelar(ActionEvent event) {
        fecharModal(event);
    }

    private void fecharModal(ActionEvent event) {
        Button btn = (Button) event.getSource();
        Stage stage = (Stage) btn.getScene().getWindow();
        stage.close();
    }

    private void mostrarAlerta(String titulo, String mensagem) {
        Alert alert = new Alert(Alert.AlertType.ERROR);
        alert.setTitle(titulo);
        alert.setHeaderText(null);
        alert.setContentText(mensagem);
        alert.showAndWait();
    }
}
