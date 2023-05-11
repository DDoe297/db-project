import sys
from datetime import date, time

import matplotlib
import psycopg2
from matplotlib.backends.backend_qt5agg import FigureCanvasQTAgg
from matplotlib.figure import Figure
from PyQt5 import QtCore, QtGui, QtWidgets
from PyQt5.QtCore import Qt
import networkx as nx
import json


matplotlib.use('Qt5Agg')


class Transaction:
    def __init__(self, row) -> None:
        (self.voucher_id,
         self.date,
         self.time,
         self.amount,
         self.source_deposit,
         self.destination_deposit,
         self.branch_id,
         self.description,
         source_inside_bank,
         destination_inside_bank) = row
        if self.source_deposit == None:
            self.source_deposit = f'Cash_{self.voucher_id}'
        if self.destination_deposit == None:
            self.destination_deposit = f'Cash_{self.voucher_id}'
        if not source_inside_bank:
            self.source_deposit = f'Outside_{self.source_deposit}'
        if not destination_inside_bank:
            self.destination_deposit = f'Outside_{self.destination_deposit}'

    def __str__(self) -> str:
        return f'{self.voucher_id}-{self.date}-{self.time}-{self.amount}-{self.source_deposit}-{self.destination_deposit}'


class TransactionGraph(FigureCanvasQTAgg):

    def __init__(self, traced_transactions, parent=None, width=10, height=7, dpi=100):
        fig = Figure(figsize=(width, height), dpi=dpi)
        self.axes = fig.add_subplot()
        graph = nx.DiGraph()
        edge_labels = {}
        for transaction in traced_transactions:
            graph.add_node(transaction.source_deposit)
            graph.add_node(transaction.destination_deposit)
            graph.add_edge(transaction.source_deposit,
                           transaction.destination_deposit)
            edge_labels[(transaction.source_deposit, transaction.destination_deposit)
                        ] = f'{transaction.amount}\n{transaction.date.strftime("%y-%m-%d")}\n{transaction.time}'
        pos = nx.planar_layout(graph)
        nx.draw(
            graph, pos, edge_color='black', width=1, linewidths=1,
            node_size=500, node_color='pink', alpha=0.9,
            labels={node: node if 'Cash' not in str(
                node) else 'Cash' for node in graph.nodes()}, ax=self.axes
        )
        nx.draw_networkx_edge_labels(
            graph, pos,
            edge_labels=edge_labels,
            font_color='red',
            ax=self.axes
        )
        super(TransactionGraph, self).__init__(fig)


class TableModel(QtCore.QAbstractTableModel):
    def __init__(self, data, columns):
        super(TableModel, self).__init__()
        self._data = data
        self._columns = columns

    def data(self, index, role):
        if role == Qt.DisplayRole:
            value = self._data[index.row()][index.column()]
            if value is not None:
                if isinstance(value, date):
                    return value.strftime('%Y-%m-%d')
                elif isinstance(value, time):
                    return value.strftime('%H:%M')
                return str(value)
            else:
                return 'NULL'

    def headerData(self, section, orientation, role):
        if role == Qt.DisplayRole:
            if orientation == Qt.Horizontal:
                return str(self._columns[section])
        return super(TableModel, self).headerData(section, orientation, role)

    def rowCount(self, index):
        return len(self._data)

    def columnCount(self, index):
        return len(self._columns)


class MainWindow(QtWidgets.QMainWindow):
    def __init__(self,credentials):
        super().__init__()
        self.credentials = credentials
        with psycopg2.connect(**self.credentials) as connection:
            cursor = connection.cursor()
            cursor.execute('SELECT * FROM trn_src_des')
            data = cursor.fetchall()
        self.columns = [
            'Voucher ID',
            'Date',
            'Time',
            'Amount',
            'Source',
            'Destination',
            'Branch ID',
            'Description',
        ]
        self.centralWidget = QtWidgets.QWidget(self)
        self.layout = QtWidgets.QVBoxLayout(self.centralWidget)
        self.data_layout = QtWidgets.QVBoxLayout()
        self.input_layout = QtWidgets.QVBoxLayout()
        self.button_and_intput_layout = QtWidgets.QHBoxLayout()
        self.input_label = QtWidgets.QLabel(
            'Please enter a transaction id for tracing:')
        self.input_edit = QtWidgets.QLineEdit()
        self.input_button = QtWidgets.QPushButton('Check')
        self.only_int_validator = QtGui.QIntValidator()
        self.input_edit.setValidator(self.only_int_validator)
        self.input_button.clicked.connect(self.trace_transaction)
        self.button_and_intput_layout.addWidget(self.input_edit)
        self.button_and_intput_layout.addWidget(self.input_button)
        self.input_layout.addWidget(self.input_label)
        self.input_layout.addLayout(self.button_and_intput_layout)
        self.table = QtWidgets.QTableView()
        self.table.horizontalHeader().setStretchLastSection(True)
        self.model = TableModel(data, self.columns)
        self.table.setModel(self.model)
        self.data_layout.addWidget(self.table)
        self.layout.addLayout(self.input_layout)
        self.layout.addLayout(self.data_layout)
        self.setCentralWidget(self.centralWidget)
        self.setWindowTitle('Transaction Tracer')
        self.setMinimumSize(900, 600)
        self.showMaximized()

    @QtCore.pyqtSlot()
    def trace_transaction(self):
        traced_transactions = []
        transaction_id = self.input_edit.text()
        with psycopg2.connect(**self.credentials) as connection:
            cursor = connection.cursor()
            cursor.execute(
                f"SELECT *,is_deposit_registered_in_bank(sourcedep) AS source_inside_bank,is_deposit_registered_in_bank(desdep) AS destination_inside_bank FROM trace_transaction('{transaction_id}')")
            rows = cursor.fetchall()
            for row in rows:
                traced_transactions.append(Transaction(row))
        self.trace_table = QtWidgets.QTableView()
        self.trace_model = TableModel(
            list(map(lambda x: x[:-2], rows)), self.columns)
        self.graph = TransactionGraph(traced_transactions)
        self.trace_table.setModel(self.trace_model)
        self.trace_table.horizontalHeader().setStretchLastSection(True)
        self.trace_window = QtWidgets.QWidget()
        self.trace_layout = QtWidgets.QVBoxLayout(self.trace_window)
        self.trace_layout.addWidget(self.trace_table)
        self.trace_layout.addWidget(self.graph)
        self.trace_window.setLayout(self.trace_layout)
        self.trace_window.setMinimumSize(900, 600)
        self.trace_window.showMaximized()
        self.trace_window.setWindowTitle('Trace Window')
        self.trace_window.show()


def import_connection_credentials():
    try:
        with open('Database.json') as file:
            return json.loads(file.read())
    except FileNotFoundError:
        return {'user': 'postgres',
                'password': 'postgres',
                'host': 'localhost',
                'port': 5432,
                'database': 'Project'}


app = QtWidgets.QApplication(sys.argv)
window = MainWindow(import_connection_credentials())
window.show()
app.exec_()
