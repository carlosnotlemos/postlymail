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
import java.io.IOException;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;

public class ClientesController {

    @FXML private TableView<Cliente> tableClientes;
    @FXML private TableColumn<Cliente, String> colNome;
    @FXML private TableColumn<Cliente, String> colEmail;
    @FXML private TableColumn<Cliente, String> colTelefone;
    @FXML private TableColumn<Cliente, LocalDateTime> colCadastro;

    @FXML private TextField txtNome;
    @FXML private TextField txtEmail;
    @FXML private TextField txtTelefone;

    private final ClienteService clienteService = new ClienteService();
    private final ObservableList<Cliente> observableClientes = FXCollections.observableArrayList();

    @FXML
    public void initialize() {
        configurarTabela();
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

    private void carregarClientes() {
        observableClientes.setAll(clienteService.listarTodos());
    }

    @FXML
    private void handleNovoCliente(ActionEvent event) {
        showClienteForm(null);
    }

    private void showClienteForm(Cliente cliente) {
        try {
            FXMLLoader loader = new FXMLLoader(getClass().getResource("/br/com/postlymail/view/ClienteFormView.fxml"));
            loader.setController(this);
            Scene scene = new Scene(loader.load());
            
            Stage dialogStage = new Stage();
            dialogStage.initModality(Modality.APPLICATION_MODAL);
            dialogStage.initStyle(StageStyle.UNDECORATED); // Modern look
            dialogStage.setScene(scene);
            
            // Clear fields if new
            if (cliente == null) {
                // txtNome and others are injected because this controller is reused or can be separate.
                // For simplicity, I'm using the same controller for the modal here, 
                // but let's make sure IDs match or use a separate controller if needed.
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

        Cliente novo = new Cliente(txtNome.getText(), txtEmail.getText(), txtTelefone.getText());
        try {
            clienteService.salvar(novo);
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
